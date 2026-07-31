import Foundation
import SwiftData

/// In-app MCP tool registry. Each tool reads from the live `ModelContainer` so writes
/// from the app are immediately visible without inter-process synchronization.
///
/// This is a deliberately smaller catalog than the stdio helper
/// (`tools/ephemeris-mcp/Sources/EphemerisMCP/Tools.swift`): the embedded HTTP server
/// exposes the five read-only summary tools, while the stdio helper carries the full
/// per-entity surface. Tools shared between the two emit identical JSON field names so
/// a client sees the same shape on either transport. Uses SwiftData FetchDescriptors
/// instead of raw SQLite. Throughline #4 invariant (preserve `source_authority` across
/// the protocol boundary) is enforced here.
@MainActor
struct MCPTool: Sendable {
    let name: String
    let description: String
    let inputSchema: MCPJSONValue
    let invoke: @MainActor ([String: MCPJSONValue], ModelContainer) -> MCPJSONValue
}

@MainActor
enum MCPTools {
    static let all: [MCPTool] = [
        listRigs,
        listNights,
        listObservations,
        getAggregateStats,
        getCorpusSummary,
        search,
        fetch,
    ]

    // MARK: - list_rigs

    static let listRigs = MCPTool(
        name: "list_rigs",
        description: "List all rig profiles in the Ephemeris library. Returns mount class, imaging-train values, computed pixel scale, and high-precision-encoders flag. Call this first to find a rig UUID to pass to other tools.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ]),
        invoke: { _, container in
            let context = ModelContext(container)
            let rigs = (try? context.fetch(FetchDescriptor<RigProfileEntity>(
                sortBy: [SortDescriptor(\.currentName)]
            ))) ?? []
            return .array(rigs.map { r in
                let scale = ImagingScale.compute(
                    focalLengthMm: r.imagingFocalLengthMm,
                    pixelSizeMicrons: r.imagingPixelSizeMicrons,
                    binning: r.imagingBinning,
                    reducerFactor: r.reducerFactor
                )
                let mountClass = MountClass(rawValue: r.mountClassRaw) ?? .standardGearMount
                let configured = scale > 0
                return .object([
                    "id": .string(r.id.uuidString),
                    "name": .string(r.currentName),
                    "mount_class": .string(r.mountClassRaw),
                    "mount_class_display": .string(mountClass.displayName),
                    "has_high_precision_encoders": .bool(r.hasHighPrecisionEncoders),
                    "imaging_focal_length_mm": .number(r.imagingFocalLengthMm),
                    "imaging_pixel_size_microns": .number(r.imagingPixelSizeMicrons),
                    "imaging_binning": .integer(r.imagingBinning),
                    "reducer_factor": r.reducerFactor.map { .number($0) } ?? .null,
                    "imaging_configured": .bool(configured),
                    "imaging_pixel_scale_arcsec_per_px": .number(scale),
                    "mount_model": r.mountModel.map { .string($0) } ?? .null,
                    "notes": r.notes.map { .string($0) } ?? .null,
                ])
            })
        }
    )

    // MARK: - list_nights

    static let listNights = MCPTool(
        name: "list_nights",
        description: "List nights in the library (most recent first). Optionally filter by rig UUID and a since-days window. Returns per-night rollups: night RMS (frame-weighted), integration time, session count, source file path.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "rig_id": .object(["type": .string("string"), "description": .string("Filter to a single rig (UUID from list_rigs)")]),
                "since_days": .object(["type": .string("integer"), "description": .string("Window in days from today")]),
                "limit": .object(["type": .string("integer"), "description": .string("Max rows (default 100)")]),
            ]),
        ]),
        invoke: { args, container in
            let context = ModelContext(container)
            let rigIDString = args["rig_id"]?.stringValue
            let rigUUID = rigIDString.flatMap { UUID(uuidString: $0) }
            // A supplied-but-unparseable rig_id must not silently fall through to
            // an unfiltered fetch — that would return the whole corpus as if it
            // were scoped to one rig.
            if rigIDString != nil && rigUUID == nil {
                return .object(["error": .string("invalid rig_id — expected a UUID from list_rigs")])
            }
            let sinceDays = args["since_days"]?.intValue
            let cutoff: Date = sinceDays.map { Date().addingTimeInterval(-Double($0) * 86400) } ?? .distantPast
            let limit = args["limit"]?.intValue ?? 100

            var descriptor = FetchDescriptor<NightRecordEntity>(
                predicate: rigUUID.map { uuid in
                    #Predicate<NightRecordEntity> { record in
                        record.rigProfile?.id == uuid && record.nightDate >= cutoff
                    }
                } ?? #Predicate<NightRecordEntity> { record in
                    record.nightDate >= cutoff
                },
                sortBy: [SortDescriptor(\.nightDate, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            let nights = (try? context.fetch(descriptor)) ?? []

            let iso = ISO8601DateFormatter()
            return .array(nights.map { n in
                .object([
                    "id": .string(n.id.uuidString),
                    "rig_id": .string(n.rigProfile?.id.uuidString ?? ""),
                    "night_date": .string(iso.string(from: n.nightDate)),
                    "sessions_count": .integer(n.sessionsCount),
                    "total_integration_minutes": .number(n.totalIntegrationMinutes),
                    "night_rms_arcsec": .number(n.medianRMSArcsec),
                    "best_session_rms_arcsec": .number(n.bestSessionRMSArcsec),
                    "worst_session_rms_arcsec": .number(n.worstSessionRMSArcsec),
                    "source_file_path": .string(n.sourceFilePath),
                    "catalog_identifier": n.catalogIdentifier.map { .string($0) } ?? .null,
                    "catalog_common_name": n.catalogCommonName.map { .string($0) } ?? .null,
                    "median_ra_hours": n.medianRAHours.map { .number($0) } ?? .null,
                    "median_dec_degrees": n.medianDecDegrees.map { .number($0) } ?? .null,
                    "galactic_latitude_deg": n.galacticLatitudeDeg.map { .number($0) } ?? .null,
                    "sub_quality": n.subQualityRaw.map { .string($0) } ?? .null,
                ])
            })
        }
    )

    // MARK: - list_observations

    static let listObservations = MCPTool(
        name: "list_observations",
        description: "List recommender observations for a rig. Returns title, summary, suggested response, severity, and source_authority for each. Sorted by severity (highest first). The source_authority field distinguishes PHD2-canon advice (phd2Manual / phd2Measurement / phd2BehaviorDocumented) from communityConsensus and ephemerisHeuristic — preserve this distinction when summarizing to the user.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "rig_id": .object(["type": .string("string"), "description": .string("Filter to a single rig (UUID from list_rigs)")]),
                "limit": .object(["type": .string("integer"), "description": .string("Max rows (default 200)")]),
            ]),
        ]),
        invoke: { args, container in
            let context = ModelContext(container)
            let rigIDString = args["rig_id"]?.stringValue
            let rigUUID = rigIDString.flatMap { UUID(uuidString: $0) }
            // A supplied-but-unparseable rig_id must not silently fall through to
            // an unfiltered fetch — that would return every rig's observations.
            if rigIDString != nil && rigUUID == nil {
                return .object(["error": .string("invalid rig_id — expected a UUID from list_rigs")])
            }
            let limit = args["limit"]?.intValue ?? 200

            var descriptor = FetchDescriptor<ObservationEntity>(
                predicate: rigUUID.map { uuid in
                    #Predicate<ObservationEntity> { obs in
                        obs.rigProfileId == uuid
                    }
                },
                sortBy: [
                    SortDescriptor(\.severityRaw, order: .reverse),
                    SortDescriptor(\.generatedAt, order: .reverse),
                ]
            )
            descriptor.fetchLimit = limit
            let observations = (try? context.fetch(descriptor)) ?? []

            let iso = ISO8601DateFormatter()
            return .array(observations.map { o in
                .object([
                    "id": .string(o.id.uuidString),
                    "night_id": o.nightRecord.map { .string($0.id.uuidString) } ?? .null,
                    "title": .string(o.title),
                    "summary": .string(o.summary),
                    "suggested_response": .string(o.suggestedResponse),
                    "session_started_at": o.sessionStartedAt.map { .string(iso.string(from: $0)) } ?? .null,
                    "category": .string(categoryName(o.categoryRaw)),
                    "severity": .string(severityName(o.severityRaw)),
                    "source_authority": .string(o.sourceAuthorityRaw),
                    "confidence": .string(o.confidenceRaw),
                    "generated_at": .string(iso.string(from: o.generatedAt)),
                ])
            })
        }
    )

    // MARK: - get_aggregate_stats

    static let getAggregateStats = MCPTool(
        name: "get_aggregate_stats",
        description: "Aggregate statistics across a rig's nights: count, median / p75 / p90 RMS, total integration time. Ground 'is my rig getting better or worse?' questions with these.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "rig_id": .object(["type": .string("string"), "description": .string("Required — UUID of the rig")]),
                "since_days": .object(["type": .string("integer"), "description": .string("Window in days from today")]),
            ]),
            "required": .array([.string("rig_id")]),
        ]),
        invoke: { args, container in
            let context = ModelContext(container)
            guard let rigIDString = args["rig_id"]?.stringValue,
                  let rigUUID = UUID(uuidString: rigIDString)
            else { return .object(["error": .string("missing or invalid rig_id")]) }

            let sinceDays = args["since_days"]?.intValue
            let cutoff: Date = sinceDays.map { Date().addingTimeInterval(-Double($0) * 86400) } ?? .distantPast
            let descriptor = FetchDescriptor<NightRecordEntity>(
                predicate: #Predicate<NightRecordEntity> { record in
                    record.rigProfile?.id == rigUUID && record.nightDate >= cutoff
                }
            )
            let nights = (try? context.fetch(descriptor)) ?? []
            let rmsValues = nights.map { $0.medianRMSArcsec }.filter { $0 > 0 }.sorted()
            guard !rmsValues.isEmpty else {
                return .object(["nights_count": .integer(0)])
            }
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

    static let getCorpusSummary = MCPTool(
        name: "get_corpus_summary",
        description: "High-level inventory of the library — rig count, total nights, total observations, oldest/newest night dates. Useful opening tool to understand what's available.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:]),
        ]),
        invoke: { _, container in
            // Counts via fetchCount and the date range via two limit-1 fetches —
            // this is the documented opening tool, so it must not materialize the
            // whole store (observations carry Data blobs) on the main actor.
            let context = ModelContext(container)
            let rigs = (try? context.fetch(FetchDescriptor<RigProfileEntity>(
                sortBy: [SortDescriptor(\.currentName)]
            ))) ?? []
            let nightCount = (try? context.fetchCount(FetchDescriptor<NightRecordEntity>())) ?? 0
            let observationCount = (try? context.fetchCount(FetchDescriptor<ObservationEntity>())) ?? 0
            var oldestFetch = FetchDescriptor<NightRecordEntity>(
                sortBy: [SortDescriptor(\.nightDate, order: .forward)]
            )
            oldestFetch.fetchLimit = 1
            var newestFetch = FetchDescriptor<NightRecordEntity>(
                sortBy: [SortDescriptor(\.nightDate, order: .reverse)]
            )
            newestFetch.fetchLimit = 1
            let oldest = (try? context.fetch(oldestFetch))?.first?.nightDate
            let newest = (try? context.fetch(newestFetch))?.first?.nightDate
            let iso = ISO8601DateFormatter()
            return .object([
                "rig_count": .integer(rigs.count),
                "night_count": .integer(nightCount),
                "observation_count": .integer(observationCount),
                "oldest_night": oldest.map { .string(iso.string(from: $0)) } ?? .null,
                "newest_night": newest.map { .string(iso.string(from: $0)) } ?? .null,
                "rig_names": .array(rigs.map { .string($0.currentName) }),
            ])
        }
    )

    // MARK: - search / fetch (ChatGPT deep-research contract)

    /// OpenAI's deep-research connectors require exactly two retrieval tools:
    /// `search` (query → result stubs) and `fetch` (id → full record). These
    /// wrap the same read-only library the domain tools expose; ids are
    /// "rig:<uuid>", "night:<uuid>", or "obs:<uuid>".
    static let search = MCPTool(
        name: "search",
        description: "Search the Ephemeris library for rigs, nights, and recommender observations matching a query. Returns result stubs with an id to pass to fetch. Matches rig names, target catalog names, night dates (ISO), observation titles and summaries.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string"), "description": .string("Free-text query; all whitespace-separated terms must match")]),
            ]),
            "required": .array([.string("query")]),
        ]),
        invoke: { args, container in
            guard let query = args["query"]?.stringValue?.trimmingCharacters(in: .whitespaces),
                  !query.isEmpty
            else { return .object(["error": .string("missing query")]) }
            let terms = query.lowercased().split(separator: " ").map(String.init)
            func matches(_ haystack: String) -> Bool {
                let lowered = haystack.lowercased()
                return terms.allSatisfy { lowered.contains($0) }
            }

            let context = ModelContext(container)
            let iso = ISO8601DateFormatter()
            var results: [MCPJSONValue] = []
            let cap = 25

            let rigs = (try? context.fetch(FetchDescriptor<RigProfileEntity>())) ?? []
            for r in rigs where matches([r.currentName, r.mountModel ?? "", r.notes ?? "", r.mountClassRaw].joined(separator: " ")) {
                results.append(.object([
                    "id": .string("rig:\(r.id.uuidString)"),
                    "title": .string("Rig: \(r.currentName)"),
                    "text": .string("\(r.mountClassRaw) · imaging \(r.imagingFocalLengthMm)mm"),
                    "url": .null,
                ]))
            }

            let nights = (try? context.fetch(FetchDescriptor<NightRecordEntity>(
                sortBy: [SortDescriptor(\.nightDate, order: .reverse)]
            ))) ?? []
            for n in nights where results.count < cap {
                let dateString = iso.string(from: n.nightDate)
                let fields = [dateString, n.catalogIdentifier ?? "", n.catalogCommonName ?? "", n.sourceFilePath]
                guard matches(fields.joined(separator: " ")) else { continue }
                let target = n.catalogCommonName ?? n.catalogIdentifier ?? "untargeted"
                results.append(.object([
                    "id": .string("night:\(n.id.uuidString)"),
                    "title": .string("Night \(dateString.prefix(10)) — \(target)"),
                    "text": .string(String(format: "%d sessions · %.0f min · night RMS %.2f\"", n.sessionsCount, n.totalIntegrationMinutes, n.medianRMSArcsec)),
                    "url": .null,
                ]))
            }

            let observations = (try? context.fetch(FetchDescriptor<ObservationEntity>(
                sortBy: [SortDescriptor(\.severityRaw, order: .reverse)]
            ))) ?? []
            for o in observations where results.count < cap {
                guard matches([o.title, o.summary].joined(separator: " ")) else { continue }
                results.append(.object([
                    "id": .string("obs:\(o.id.uuidString)"),
                    "title": .string(o.title),
                    "text": .string(String(o.summary.prefix(200))),
                    "url": .null,
                ]))
            }

            return .object(["results": .array(Array(results.prefix(cap)))])
        }
    )

    static let fetch = MCPTool(
        name: "fetch",
        description: "Fetch the full record for a search result id (rig:<uuid>, night:<uuid>, or obs:<uuid>). Returns the complete entity as JSON text.",
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("string"), "description": .string("An id returned by search")]),
            ]),
            "required": .array([.string("id")]),
        ]),
        invoke: { args, container in
            guard let id = args["id"]?.stringValue else {
                return .object(["error": .string("missing id")])
            }
            let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let uuid = UUID(uuidString: parts[1]) else {
                return .object(["error": .string("invalid id — expected rig:<uuid>, night:<uuid>, or obs:<uuid>")])
            }
            let context = ModelContext(container)
            let iso = ISO8601DateFormatter()

            switch parts[0] {
            case "rig":
                let found = (try? context.fetch(FetchDescriptor<RigProfileEntity>(
                    predicate: #Predicate { $0.id == uuid }
                )))?.first
                guard let r = found else { return .object(["error": .string("rig not found")]) }
                return .object([
                    "id": .string(id),
                    "title": .string("Rig: \(r.currentName)"),
                    "text": MCPJSONValue.string(MCPJSONFormatter.toPrettyString(.object([
                        "name": .string(r.currentName),
                        "mount_class": .string(r.mountClassRaw),
                        "mount_model": r.mountModel.map { .string($0) } ?? .null,
                        "has_high_precision_encoders": .bool(r.hasHighPrecisionEncoders),
                        "imaging_focal_length_mm": .number(r.imagingFocalLengthMm),
                        "imaging_pixel_size_microns": .number(r.imagingPixelSizeMicrons),
                        "imaging_binning": .integer(r.imagingBinning),
                        "notes": r.notes.map { .string($0) } ?? .null,
                    ]))),
                    "url": .null,
                    "metadata": .object(["type": .string("rig")]),
                ])
            case "night":
                let found = (try? context.fetch(FetchDescriptor<NightRecordEntity>(
                    predicate: #Predicate { $0.id == uuid }
                )))?.first
                guard let n = found else { return .object(["error": .string("night not found")]) }
                return .object([
                    "id": .string(id),
                    "title": .string("Night \(iso.string(from: n.nightDate).prefix(10))"),
                    "text": MCPJSONValue.string(MCPJSONFormatter.toPrettyString(.object([
                        "night_date": .string(iso.string(from: n.nightDate)),
                        "rig": .string(n.rigProfile?.currentName ?? ""),
                        "sessions_count": .integer(n.sessionsCount),
                        "total_integration_minutes": .number(n.totalIntegrationMinutes),
                        "night_rms_arcsec": .number(n.medianRMSArcsec),
                        "best_session_rms_arcsec": .number(n.bestSessionRMSArcsec),
                        "worst_session_rms_arcsec": .number(n.worstSessionRMSArcsec),
                        "catalog_identifier": n.catalogIdentifier.map { .string($0) } ?? .null,
                        "catalog_common_name": n.catalogCommonName.map { .string($0) } ?? .null,
                        "sub_quality": n.subQualityRaw.map { .string($0) } ?? .null,
                        "source_file_path": .string(n.sourceFilePath),
                    ]))),
                    "url": .null,
                    "metadata": .object(["type": .string("night")]),
                ])
            case "obs":
                let found = (try? context.fetch(FetchDescriptor<ObservationEntity>(
                    predicate: #Predicate { $0.id == uuid }
                )))?.first
                guard let o = found else { return .object(["error": .string("observation not found")]) }
                return .object([
                    "id": .string(id),
                    "title": .string(o.title),
                    "text": MCPJSONValue.string(MCPJSONFormatter.toPrettyString(.object([
                        "title": .string(o.title),
                        "summary": .string(o.summary),
                        "suggested_response": .string(o.suggestedResponse),
                        "category": .string(categoryName(o.categoryRaw)),
                        "severity": .string(severityName(o.severityRaw)),
                        "source_authority": .string(o.sourceAuthorityRaw),
                        "confidence": .string(o.confidenceRaw),
                        "session_started_at": o.sessionStartedAt.map { .string(iso.string(from: $0)) } ?? .null,
                        "generated_at": .string(iso.string(from: o.generatedAt)),
                    ]))),
                    "url": .null,
                    "metadata": .object(["type": .string("observation")]),
                ])
            default:
                return .object(["error": .string("unknown id prefix — expected rig:, night:, or obs:")])
            }
        }
    )

    // MARK: - Helpers

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
