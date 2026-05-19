import Foundation

/// Tool registry for the MCP server.
/// Each Tool declares its MCP schema and a function that, given args + the store,
/// returns a JSON-serializable result.
struct Tool: Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
    let invoke: @Sendable ([String: JSONValue], LibraryStore) -> JSONValue
}

enum Tools {
    static let all: [Tool] = [
        listRigs,
        listNights,
        listObservations,
        getAggregateStats,
        getCorpusSummary,
    ]

    // MARK: - list_rigs

    static let listRigs = Tool(
        name: "list_rigs",
        description: """
        List all rig profiles in the Ephemeris library. Returns the rig's name, mount class,
        imaging-train values, and a count of associated nights. Use this first to find
        the rig UUID to pass to other tools.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
        ]),
        invoke: { _, store in
            let rigs = store.listRigs()
            return .array(rigs.map { r in
                .object([
                    "id": .string(r.uuid),
                    "name": .string(r.currentName),
                    "mount_class": .string(r.mountClass),
                    "has_high_precision_encoders": .bool(r.hasHighPrecisionEncoders),
                    "imaging_focal_length_mm": .number(r.imagingFocalLengthMm),
                    "imaging_pixel_size_microns": .number(r.imagingPixelSizeMicrons),
                    "imaging_binning": .integer(r.imagingBinning),
                    "imaging_pixel_scale_arcsec_per_px": .number(
                        r.imagingFocalLengthMm > 0 && r.imagingPixelSizeMicrons > 0
                            ? 206.265 * r.imagingPixelSizeMicrons * Double(r.imagingBinning) / r.imagingFocalLengthMm
                            : 0
                    ),
                    "mount_model": r.mountModel.map { .string($0) } ?? .null,
                    "notes": r.notes.map { .string($0) } ?? .null,
                ])
            })
        }
    )

    // MARK: - list_nights

    static let listNights = Tool(
        name: "list_nights",
        description: """
        List nights in the library, most recent first. Optionally filter by rig UUID and
        a since-days window. Returns per-night rollups: median RMS, integration time,
        session count, source file path.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "rig_id": .object(["type": "string", "description": "Filter to a single rig"]),
                "since_days": .object(["type": "integer", "description": "Window in days from today"]),
                "limit": .object(["type": "integer", "description": "Max rows (default 100)"]),
            ]),
        ]),
        invoke: { args, store in
            let rigUUID = args["rig_id"]?.stringValue
            let sinceDays = args["since_days"]?.intValue
            let limit = args["limit"]?.intValue ?? 100
            let nights = store.listNights(rigUUID: rigUUID, sinceDays: sinceDays, limit: limit)
            return .array(nights.map { n in
                .object([
                    "id": .string(n.uuid),
                    "rig_id": .string(n.rigUUID),
                    "night_date": .string(ISO8601DateFormatter().string(from: n.nightDate)),
                    "sessions_count": .integer(n.sessionsCount),
                    "total_integration_minutes": .number(n.totalIntegrationMinutes),
                    "median_rms_arcsec": .number(n.medianRMSArcsec),
                    "best_session_rms_arcsec": .number(n.bestSessionRMSArcsec),
                    "worst_session_rms_arcsec": .number(n.worstSessionRMSArcsec),
                    "source_file_path": .string(n.sourceFilePath),
                ])
            })
        }
    )

    // MARK: - list_observations

    static let listObservations = Tool(
        name: "list_observations",
        description: """
        List recommender observations for a rig. Returns the title, summary, suggested response,
        severity, and source authority for each. Sorted by severity (highest first).
        The source authority field distinguishes PHD2-canon advice from Ephemeris heuristics.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "rig_id": .object(["type": "string", "description": "Filter to a single rig"]),
                "limit": .object(["type": "integer", "description": "Max rows (default 200)"]),
            ]),
        ]),
        invoke: { args, store in
            let rigUUID = args["rig_id"]?.stringValue
            let limit = args["limit"]?.intValue ?? 200
            let observations = store.listObservations(rigUUID: rigUUID, limit: limit)
            return .array(observations.map { o in
                .object([
                    "id": .string(o.uuid),
                    "night_id": .string(o.nightUUID),
                    "title": .string(o.title),
                    "summary": .string(o.summary),
                    "suggested_response": .string(o.suggestedResponse),
                    "category": .string(categoryName(o.categoryRaw)),
                    "severity": .string(severityName(o.severityRaw)),
                    "source_authority": .string(o.sourceAuthority),
                    "confidence": .string(o.confidence),
                    "generated_at": .string(ISO8601DateFormatter().string(from: o.generatedAt)),
                ])
            })
        }
    )

    // MARK: - get_aggregate_stats

    static let getAggregateStats = Tool(
        name: "get_aggregate_stats",
        description: """
        Get aggregate statistics across a rig's nights: count, median RMS, p75, p90, total
        integration time. Useful for grounding "is my rig getting better or worse?" questions.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "rig_id": .object(["type": "string", "description": "Required — UUID of the rig"]),
                "since_days": .object(["type": "integer", "description": "Window in days from today"]),
            ]),
            "required": .array(["rig_id"]),
        ]),
        invoke: { args, store in
            guard let rigUUID = args["rig_id"]?.stringValue else {
                return .object(["error": "missing rig_id"])
            }
            let sinceDays = args["since_days"]?.intValue
            let nights = store.listNights(rigUUID: rigUUID, sinceDays: sinceDays, limit: 10_000)
            let rmsValues = nights.map { $0.medianRMSArcsec }.filter { $0 > 0 }.sorted()
            guard !rmsValues.isEmpty else { return .object(["nights_count": .integer(0)]) }
            let median = rmsValues[rmsValues.count / 2]
            let p75 = rmsValues[Int(Double(rmsValues.count) * 0.75)]
            let p90 = rmsValues[Int(Double(rmsValues.count) * 0.90)]
            let totalMin = nights.reduce(0.0) { $0 + $1.totalIntegrationMinutes }
            return .object([
                "nights_count": .integer(nights.count),
                "median_rms_arcsec": .number(median),
                "p75_rms_arcsec": .number(p75),
                "p90_rms_arcsec": .number(p90),
                "best_rms_arcsec": .number(rmsValues.first ?? 0),
                "worst_rms_arcsec": .number(rmsValues.last ?? 0),
                "total_integration_hours": .number(totalMin / 60),
                "window_days": sinceDays.map { .integer($0) } ?? .null,
            ])
        }
    )

    // MARK: - get_corpus_summary

    static let getCorpusSummary = Tool(
        name: "get_corpus_summary",
        description: """
        High-level summary of everything in the library — useful as an opening tool to
        understand what's available before drilling in. Returns rig count, total nights,
        total observations, oldest/newest night dates.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([:]),
        ]),
        invoke: { _, store in
            let rigs = store.listRigs()
            let nights = store.listNights(limit: 10_000)
            let observations = store.listObservations(limit: 10_000)
            let dates = nights.map { $0.nightDate }
            return .object([
                "rig_count": .integer(rigs.count),
                "night_count": .integer(nights.count),
                "observation_count": .integer(observations.count),
                "oldest_night": (dates.min()).map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
                "newest_night": (dates.max()).map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
                "rig_names": .array(rigs.map { .string($0.currentName) }),
            ])
        }
    )

    private static func categoryName(_ raw: Int) -> String {
        switch raw {
        case 0: return "subQuality"
        case 1: return "opticalTrain"
        case 2: return "equipment"
        case 3: return "phd2Hygiene"
        case 4: return "pattern"
        case 5: return "suggestion"
        default: return "unknown"
        }
    }

    private static func severityName(_ raw: Int) -> String {
        switch raw {
        case 5: return "alert"
        case 4: return "pattern"
        case 3: return "equipment"
        case 2: return "hygiene"
        case 1: return "suggestion"
        case 0: return "coaching"
        default: return "unknown"
        }
    }
}
