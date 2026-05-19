import Foundation
import SwiftData

/// In-app MCP tool registry. Each tool reads from the live `ModelContainer` so writes
/// from the app are immediately visible without inter-process synchronization.
///
/// Tool catalog matches the stdio helper (`tools/ephemeris-mcp/Sources/EphemerisMCP/Tools.swift`)
/// but uses SwiftData FetchDescriptors instead of raw SQLite. Throughline #4 invariant
/// (preserve `source_authority` across the protocol boundary) is enforced here.
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
                return .object([
                    "id": .string(r.id.uuidString),
                    "name": .string(r.currentName),
                    "mount_class": .string(r.mountClassRaw),
                    "has_high_precision_encoders": .bool(r.hasHighPrecisionEncoders),
                    "imaging_focal_length_mm": .number(r.imagingFocalLengthMm),
                    "imaging_pixel_size_microns": .number(r.imagingPixelSizeMicrons),
                    "imaging_binning": .integer(r.imagingBinning),
                    "reducer_factor": r.reducerFactor.map { .number($0) } ?? .null,
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
        description: "List nights in the library (most recent first). Optionally filter by rig UUID and a since-days window. Returns per-night rollups: median RMS, integration time, session count, source file path.",
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
                    "median_rms_arcsec": .number(n.medianRMSArcsec),
                    "best_session_rms_arcsec": .number(n.bestSessionRMSArcsec),
                    "worst_session_rms_arcsec": .number(n.worstSessionRMSArcsec),
                    "source_file_path": .string(n.sourceFilePath),
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
            let context = ModelContext(container)
            let rigs = (try? context.fetch(FetchDescriptor<RigProfileEntity>())) ?? []
            let nights = (try? context.fetch(FetchDescriptor<NightRecordEntity>())) ?? []
            let observations = (try? context.fetch(FetchDescriptor<ObservationEntity>())) ?? []
            let dates = nights.map { $0.nightDate }
            let iso = ISO8601DateFormatter()
            return .object([
                "rig_count": .integer(rigs.count),
                "night_count": .integer(nights.count),
                "observation_count": .integer(observations.count),
                "oldest_night": dates.min().map { .string(iso.string(from: $0)) } ?? .null,
                "newest_night": dates.max().map { .string(iso.string(from: $0)) } ?? .null,
                "rig_names": .array(rigs.map { .string($0.currentName) }),
            ])
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
