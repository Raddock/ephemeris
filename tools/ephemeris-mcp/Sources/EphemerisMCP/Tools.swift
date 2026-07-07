import Foundation

/// Tool registry for the MCP server.
/// Each Tool declares its MCP schema and a function that, given args + the store,
/// returns a JSON-serializable result. Throwing a `JSONRPCError` rejects the call
/// at the protocol level (used for validation failures such as an unknown
/// annotation category) instead of silently storing or degrading.
struct Tool: Sendable {
    let name: String
    let description: String
    let inputSchema: JSONValue
    let invoke: @Sendable ([String: JSONValue], LibraryStore) throws -> JSONValue
}

enum Tools {
    /// All registered tools. The write tool `add_annotation` is included only when
    /// the `EPHEMERIS_MCP_ALLOW_WRITES=1` environment variable is set — per design §8,
    /// writes are opt-in. The user toggles this from the MCP Server settings tab
    /// (which re-renders the `claude_desktop_config.json` entry with the env block).
    static var all: [Tool] {
        var tools: [Tool] = [
            listRigs,
            getRig,
            listNights,
            getNight,
            listSessions,
            listObservations,
            getObservation,
            listAnnotations,
            listGAResults,
            listTargets,
            getHelpTopic,
            getAggregateStats,
            getCorpusSummary,
        ]
        if ProcessInfo.processInfo.environment["EPHEMERIS_MCP_ALLOW_WRITES"] == "1" {
            tools.append(addAnnotation)
        }
        return tools
    }

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
            return .array(rigs.map { rigObject($0) })
        }
    )

    /// Imaging pixel scale in arcsec/px, matching the app's `ImagingScale.compute`:
    /// 206.265 × pixel_size_μm × binning / (focal_length_mm × reducer_factor).
    /// A reducer factor < 1 shortens effective focal length; nil is treated as 1.0.
    /// Returns nil when the imaging train isn't configured.
    private static func imagingScale(for r: LibraryStore.RigRow) -> Double? {
        guard r.imagingFocalLengthMm > 0, r.imagingPixelSizeMicrons > 0, r.imagingBinning > 0 else { return nil }
        let effectiveFL = r.imagingFocalLengthMm * (r.reducerFactor ?? 1.0)
        guard effectiveFL > 0 else { return nil }
        return 206.265 * r.imagingPixelSizeMicrons * Double(r.imagingBinning) / effectiveFL
    }

    private static func mountClassDisplay(_ raw: String) -> String {
        switch raw {
        case "standardGearMount":   return "Standard gear / belt mount"
        case "encoderBasedPremium": return "Encoder-based premium mount (e.g. 10Micron, AP, Planewave)"
        case "harmonicStrainWave":  return "Harmonic strain-wave mount (e.g. ZWO AM5, iOptron HEM)"
        case "adaptiveOptics":      return "Adaptive optics device"
        default:                    return raw
        }
    }

    /// Plain-English summary so opening tool calls give Claude enough rig context
    /// without requiring it to interpret raw fields. Flags missing setup explicitly.
    private static func rigDescription(_ r: LibraryStore.RigRow) -> String {
        var parts: [String] = []
        parts.append(r.currentName)
        parts.append(mountClassDisplay(r.mountClass))
        if let model = r.mountModel, !model.isEmpty {
            parts.append("mount: \(model)")
        }
        if let scale = imagingScale(for: r) {
            var line = String(
                format: "imaging: %.0f mm focal × %.2f µm pixel × bin %d",
                r.imagingFocalLengthMm, r.imagingPixelSizeMicrons, r.imagingBinning
            )
            if let reducer = r.reducerFactor {
                line += String(format: " × %.2f reducer", reducer)
            }
            line += String(format: " → %.2f″/px", scale)
            parts.append(line)
        } else {
            parts.append("imaging train NOT configured (no focal length / pixel size on profile — recommendations that depend on imaging scale will be wrong)")
        }
        if let notes = r.notes, !notes.isEmpty {
            parts.append("notes: \(notes)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - get_rig

    static let getRig = Tool(
        name: "get_rig",
        description: """
        Fetch a single rig profile by UUID with the same fields as list_rigs.
        Use when you already have a `rig_id` (e.g. from list_nights) and want the
        rig's hardware context without re-listing everything.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "rig_id": .object(["type": "string", "description": "UUID of the rig"]),
            ]),
            "required": .array(["rig_id"]),
        ]),
        invoke: { args, store in
            guard let id = args["rig_id"]?.stringValue, let r = store.rig(uuid: id) else {
                return .object(["error": "rig not found"])
            }
            return rigObject(r)
        }
    )

    static func rigJSON(_ r: LibraryStore.RigRow) -> JSONValue { rigObject(r) }
    static func nightJSON(_ n: LibraryStore.NightRow) -> JSONValue { nightObject(n) }
    static func observationJSON(_ o: LibraryStore.ObservationRow) -> JSONValue { observationObject(o) }

    private static func rigObject(_ r: LibraryStore.RigRow) -> JSONValue {
        let scale = imagingScale(for: r)
        return .object([
            "id": .string(r.uuid),
            "name": .string(r.currentName),
            "mount_class": .string(r.mountClass),
            "mount_class_display": .string(mountClassDisplay(r.mountClass)),
            "has_high_precision_encoders": .bool(r.hasHighPrecisionEncoders),
            "imaging_focal_length_mm": .number(r.imagingFocalLengthMm),
            "imaging_pixel_size_microns": .number(r.imagingPixelSizeMicrons),
            "imaging_binning": .integer(r.imagingBinning),
            "reducer_factor": r.reducerFactor.map { .number($0) } ?? .null,
            "imaging_pixel_scale_arcsec_per_px": .number(scale ?? 0),
            "imaging_configured": .bool(scale != nil),
            "mount_model": r.mountModel.map { .string($0) } ?? .null,
            "notes": r.notes.map { .string($0) } ?? .null,
            "description": .string(rigDescription(r)),
        ])
    }

    // MARK: - list_nights

    static let listNights = Tool(
        name: "list_nights",
        description: """
        List nights in the library, most recent first. Optionally filter by rig UUID and
        a since-days window. Returns per-night rollups: night RMS (frame-weighted), integration time,
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
            return .array(nights.map { nightObject($0) })
        }
    )

    // MARK: - get_night

    static let getNight = Tool(
        name: "get_night",
        description: """
        Fetch a single night by UUID with full pointing context, sub-quality verdict,
        and catalog match (when within tolerance). Use after list_nights to drill in.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "night_id": .object(["type": "string", "description": "UUID of the night"]),
            ]),
            "required": .array(["night_id"]),
        ]),
        invoke: { args, store in
            guard let id = args["night_id"]?.stringValue, let n = store.night(uuid: id) else {
                return .object(["error": "night not found"])
            }
            return nightObject(n)
        }
    )

    private static func nightObject(_ n: LibraryStore.NightRow) -> JSONValue {
        .object([
            "id": .string(n.uuid),
            "rig_id": .string(n.rigUUID),
            "night_date": .string(ISO8601DateFormatter().string(from: n.nightDate)),
            "sessions_count": .integer(n.sessionsCount),
            "total_integration_minutes": .number(n.totalIntegrationMinutes),
            "night_rms_arcsec": .number(n.medianRMSArcsec),
            "best_session_rms_arcsec": .number(n.bestSessionRMSArcsec),
            "worst_session_rms_arcsec": .number(n.worstSessionRMSArcsec),
            "source_file_path": .string(n.sourceFilePath),
            "sub_quality": n.subQualityRaw.map { .string($0) } ?? .null,
            "median_ra_hours": n.medianRAHours.map { .number($0) } ?? .null,
            "median_dec_degrees": n.medianDecDegrees.map { .number($0) } ?? .null,
            "galactic_latitude_deg": n.galacticLatitudeDeg.map { .number($0) } ?? .null,
            "catalog_identifier": n.catalogIdentifier.map { .string($0) } ?? .null,
            "catalog_common_name": n.catalogCommonName.map { .string($0) } ?? .null,
        ])
    }

    // MARK: - list_sessions

    static let listSessions = Tool(
        name: "list_sessions",
        description: """
        List per-session detail within a night (or across a rig). Returns one row per
        PHD2 guide session with: started_at, duration_sec, rms_total_arcsec (and RA/Dec
        breakdown), peak excursions, drift (arcsec/min), polar-align error, included/
        excluded frame counts, plus header-derived pointing context: ra_hours, dec_degrees,
        hour_angle_hours, altitude_degrees, azimuth_degrees, pier_side, hfd_pixels,
        exposure_ms, multi_star_enabled. Pass `night_id` to drill into one night, or
        `rig_id` to scan a rig's sessions. Useful for time-of-night / pointing-dependent
        hypotheses that per-night rollups can't answer (cooldown, meridian-flip cleanup,
        altitude-vs-RMS, etc.).
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "night_id": .object(["type": "string", "description": "Filter to one night by UUID"]),
                "rig_id": .object(["type": "string", "description": "Filter to a rig by UUID"]),
                "limit": .object(["type": "integer", "description": "Max rows (default 1000)"]),
            ]),
        ]),
        invoke: { args, store in
            let nightUUID = args["night_id"]?.stringValue
            let rigUUID = args["rig_id"]?.stringValue
            let limit = args["limit"]?.intValue ?? 1_000
            let rows = store.listSessions(nightUUID: nightUUID, rigUUID: rigUUID, limit: limit)
            let iso = ISO8601DateFormatter()
            return .array(rows.map { r in
                let obj: [String: JSONValue] = [
                    "id": .string(r.uuid),
                    "night_id": .string(r.nightUUID),
                    "session_index": .integer(r.sessionIndex),
                    "started_at": r.startedAt.map { .string(iso.string(from: $0)) } ?? .null,
                    "duration_sec": .number(r.durationSec),
                    "rms_total_arcsec": .number(r.rmsTotalArcsec),
                    "rms_ra_arcsec": .number(r.rmsRAArcsec),
                    "rms_dec_arcsec": .number(r.rmsDecArcsec),
                    "peak_ra_arcsec": .number(r.peakRAArcsec),
                    "peak_dec_arcsec": .number(r.peakDecArcsec),
                    "drift_ra_arcsec_per_min": .number(r.driftRAArcsecPerMin),
                    "drift_dec_arcsec_per_min": .number(r.driftDecArcsecPerMin),
                    "polar_align_error_arcmin": .number(r.polarAlignErrorArcmin),
                    "included_frames": .integer(r.includedFrames),
                    "excluded_frames": .integer(r.excludedFrames),
                    "pixel_scale_arcsec_per_px": .number(r.pixelScale),
                    "multi_star_enabled": .bool(r.multiStarEnabled),
                    "ra_hours": r.raHours.map { .number($0) } ?? .null,
                    "dec_degrees": r.decDegrees.map { .number($0) } ?? .null,
                    "hour_angle_hours": r.hourAngleHours.map { .number($0) } ?? .null,
                    "altitude_degrees": r.altitudeDegrees.map { .number($0) } ?? .null,
                    "azimuth_degrees": r.azimuthDegrees.map { .number($0) } ?? .null,
                    "pier_side": r.pierSide.map { .string($0) } ?? .null,
                    "hfd_pixels": r.hfdPixels.map { .number($0) } ?? .null,
                    "exposure_ms": r.exposureMs.map { .integer($0) } ?? .null,
                ]
                return .object(obj)
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
            return .array(observations.map { observationObject($0) })
        }
    )

    private static func observationObject(_ o: LibraryStore.ObservationRow) -> JSONValue {
        .object([
            "id": .string(o.uuid),
            // JSON null (not "") for unlinked observations — matches the embedded server.
            "night_id": o.nightUUID.map { .string($0) } ?? .null,
            "title": .string(o.title),
            "summary": .string(o.summary),
            "suggested_response": .string(o.suggestedResponse),
            "category": .string(categoryName(o.categoryRaw)),
            "severity": .string(severityName(o.severityRaw)),
            "source_authority": .string(o.sourceAuthority),
            "confidence": .string(o.confidence),
            "generated_at": .string(ISO8601DateFormatter().string(from: o.generatedAt)),
        ])
    }

    // MARK: - get_observation

    static let getObservation = Tool(
        name: "get_observation",
        description: """
        Fetch a single observation by UUID. Same fields as list_observations.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "observation_id": .object(["type": "string", "description": "UUID of the observation"]),
            ]),
            "required": .array(["observation_id"]),
        ]),
        invoke: { args, store in
            guard let id = args["observation_id"]?.stringValue, let o = store.observation(uuid: id) else {
                return .object(["error": "observation not found"])
            }
            return observationObject(o)
        }
    )

    // MARK: - list_annotations

    static let listAnnotations = Tool(
        name: "list_annotations",
        description: """
        List user-recorded annotations — equipment changes, calibration events, software updates,
        environment notes — that the recommender uses to attribute step-changes in trend data.
        Filter by `rig_id` or `night_id`. Most recent first.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "rig_id": .object(["type": "string", "description": "Filter to a rig"]),
                "night_id": .object(["type": "string", "description": "Filter to one night"]),
                "limit": .object(["type": "integer", "description": "Max rows (default 200)"]),
            ]),
        ]),
        invoke: { args, store in
            let rigUUID = args["rig_id"]?.stringValue
            let nightUUID = args["night_id"]?.stringValue
            let limit = args["limit"]?.intValue ?? 200
            let rows = store.listAnnotations(rigUUID: rigUUID, nightUUID: nightUUID, limit: limit)
            let iso = ISO8601DateFormatter()
            return .array(rows.map { a in
                .object([
                    "id": .string(a.uuid),
                    "night_id": a.nightUUID.map { .string($0) } ?? .null,
                    "rig_id": .string(a.rigProfileId),
                    "event_date": .string(iso.string(from: a.eventDate)),
                    "label": .string(a.label),
                    "detail": .string(a.detail),
                    "is_rig_mutating": .bool(a.isRigMutating),
                    "categories": .array(a.categories.map { .string($0) }),
                    "created_at": .string(iso.string(from: a.createdAt)),
                ])
            })
        }
    )

    // MARK: - list_ga_results

    static let listGAResults = Tool(
        name: "list_ga_results",
        description: """
        List parsed PHD2 Guiding Assistant runs. Returns recommended RA/Dec min-move,
        polar-alignment error, Dec backlash, peak-to-peak RA, max rate of change, and
        high-frequency star motion — all measured by PHD2 itself (phd2Measurement
        source authority). Filter by `rig_id` or `night_id`. Most recent first.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "rig_id": .object(["type": "string", "description": "Filter to a rig"]),
                "night_id": .object(["type": "string", "description": "Filter to one night"]),
                "limit": .object(["type": "integer", "description": "Max rows (default 200)"]),
            ]),
        ]),
        invoke: { args, store in
            let rigUUID = args["rig_id"]?.stringValue
            let nightUUID = args["night_id"]?.stringValue
            let limit = args["limit"]?.intValue ?? 200
            let rows = store.listGAResults(rigUUID: rigUUID, nightUUID: nightUUID, limit: limit)
            let iso = ISO8601DateFormatter()
            return .array(rows.map { g in
                .object([
                    "id": .string(g.uuid),
                    "night_id": g.nightUUID.map { .string($0) } ?? .null,
                    "rig_id": .string(g.rigProfileId),
                    "run_at": .string(iso.string(from: g.runAt)),
                    "duration_sec": .integer(g.durationSec),
                    "recommended_ra_min_move_px": g.recommendedRAMinMovePx.map { .number($0) } ?? .null,
                    "recommended_dec_min_move_px": g.recommendedDecMinMovePx.map { .number($0) } ?? .null,
                    "recommended_exposure_sec": g.recommendedExposureSec.map { .number($0) } ?? .null,
                    "polar_align_error_arcmin": g.polarAlignErrorArcmin.map { .number($0) } ?? .null,
                    "dec_backlash_ms": g.decBacklashMs.map { .number($0) } ?? .null,
                    "ra_peak_to_peak_arcsec": g.raPeakToPeakArcsec.map { .number($0) } ?? .null,
                    "ra_max_rate_of_change_arcsec_per_sec": g.raMaxRateOfChangeArcsecPerSec.map { .number($0) } ?? .null,
                    "high_freq_star_motion_arcsec_rms": g.highFreqStarMotionArcsecRMS.map { .number($0) } ?? .null,
                ])
            })
        }
    )

    // MARK: - list_targets

    static let listTargets = Tool(
        name: "list_targets",
        description: """
        List target clusters — sessions grouped by RA/Dec proximity into the same
        sky object. Returns the catalog match (if any), session count, total
        integration time, and median RMS per target so you can compare guiding
        performance across different sky objects on the same rig.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "rig_id": .object(["type": "string", "description": "Filter to a rig"]),
                "limit": .object(["type": "integer", "description": "Max rows (default 100)"]),
            ]),
        ]),
        invoke: { args, store in
            let rigUUID = args["rig_id"]?.stringValue
            let limit = args["limit"]?.intValue ?? 100
            let rows = store.listTargets(rigUUID: rigUUID, limit: limit)
            return .array(rows.map { t in
                .object([
                    "id": .string(t.uuid),
                    "rig_id": .string(t.rigUUID),
                    "center_ra_hours": .number(t.centerRA),
                    "center_dec_degrees": .number(t.centerDec),
                    "radius_deg": .number(t.radiusDeg),
                    "catalog_match": t.catalogMatch.map { .string($0) } ?? .null,
                    "session_count": .integer(t.sessionCount),
                    "total_integration_minutes": .number(t.totalIntegrationMinutes),
                    "median_rms_arcsec": .number(t.medianRMSArcsec),
                    "night_record_ids": .array(t.nightRecordIds.map { .string($0) }),
                ])
            })
        }
    )

    // MARK: - get_help_topic

    static let getHelpTopic = Tool(
        name: "get_help_topic",
        description: """
        Fetch a help topic's title + short description by ID. Use this to expand
        the `related_help_topic_ids` returned on observations into human-readable
        titles, or to suggest a learn-more topic when answering a question.
        Returns { id, title, summary }. If the ID is unknown, returns {error}.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "topic_id": .object(["type": "string", "description": "Help topic ID (e.g. 'variable-exposure-delays')"]),
            ]),
            "required": .array(["topic_id"]),
        ]),
        invoke: { args, _ in
            guard let id = args["topic_id"]?.stringValue else {
                return .object(["error": "missing topic_id"])
            }
            guard let topic = HelpCatalog.topic(id: id) else {
                return .object(["error": .string("unknown topic_id: \(id)")])
            }
            return .object([
                "id": .string(topic.id),
                "title": .string(topic.title),
                "summary": .string(topic.summary),
            ])
        }
    )

    // MARK: - add_annotation (opt-in write)

    static let addAnnotation = Tool(
        name: "add_annotation",
        description: """
        Record an annotation — equipment change, calibration event, software update,
        environment note — that the cross-night recommender uses to attribute step-changes.
        Either `night_id` or no `night_id` (a rig-level annotation, attached to no specific night)
        is valid. `categories` accepts: equipment, calibration, environment, software, freeText.
        Set `is_rig_mutating: true` for events that change the rig's identity (e.g. a guide-train
        swap) so the engine knows to bin pre/post separately. Annotations appear in the app
        on next launch / library refresh.
        """,
        inputSchema: .object([
            "type": "object",
            "properties": .object([
                "rig_id":         .object(["type": "string", "description": "Rig UUID (required)"]),
                "night_id":       .object(["type": "string", "description": "Night UUID (optional — omit for rig-level annotation)"]),
                "event_date":     .object(["type": "string", "description": "ISO8601 timestamp of the event (defaults to now if omitted)"]),
                "label":          .object(["type": "string", "description": "Short title for the event"]),
                "detail":         .object(["type": "string", "description": "Longer explanation"]),
                "categories":     .object(["type": "array", "description": "One or more of: equipment, calibration, environment, software, freeText"]),
                "is_rig_mutating": .object(["type": "boolean", "description": "True when this event changes rig identity"]),
            ]),
            "required": .array(["rig_id", "label"]),
        ]),
        invoke: { args, store in
            guard let rigID = args["rig_id"]?.stringValue, !rigID.isEmpty else {
                throw JSONRPCError(code: -32602, message: "missing rig_id", data: nil)
            }
            let label = args["label"]?.stringValue ?? ""
            guard !label.isEmpty else {
                throw JSONRPCError(code: -32602, message: "missing label", data: nil)
            }
            let nightID = args["night_id"]?.stringValue
            let detail = args["detail"]?.stringValue ?? ""
            let isMutating = args["is_rig_mutating"]?.boolValue ?? false

            // Validate categories against the app's AnnotationCategory raw values —
            // an unknown string must reject the call, not be silently stored where
            // the app would drop it on decode.
            let allowedCategories = ["equipment", "calibration", "environment", "software", "freeText"]
            var categories: [String] = []
            switch args["categories"] {
            case nil, .some(.null):
                break  // omitted — no categories
            case .some(.array(let arr)):
                for entry in arr {
                    guard let s = entry.stringValue, allowedCategories.contains(s) else {
                        let got = entry.stringValue ?? JSONFormatter.toPrettyString(entry)
                        throw JSONRPCError(
                            code: -32602,
                            message: "unknown annotation category \"\(got)\"; allowed values: \(allowedCategories.joined(separator: ", "))",
                            data: nil
                        )
                    }
                    categories.append(s)
                }
            case .some:
                throw JSONRPCError(
                    code: -32602,
                    message: "categories must be an array of strings; allowed values: \(allowedCategories.joined(separator: ", "))",
                    data: nil
                )
            }

            // The rig must exist — an annotation against a phantom rig UUID would be
            // invisible in the app forever.
            guard store.rig(uuid: rigID) != nil else {
                throw JSONRPCError(code: -32602, message: "rig not found: \(rigID)", data: nil)
            }
            // A supplied night_id must resolve; only an *omitted* night_id means
            // "rig-level annotation". Don't silently degrade.
            if let nightID {
                guard store.night(uuid: nightID) != nil else {
                    throw JSONRPCError(code: -32602, message: "night not found: \(nightID)", data: nil)
                }
            }

            let eventDate: Date
            if let s = args["event_date"]?.stringValue, let d = ISO8601DateFormatter().date(from: s) {
                eventDate = d
            } else {
                eventDate = Date()
            }
            guard let newID = store.addAnnotation(
                rigProfileId: rigID,
                nightUUID: nightID,
                eventDate: eventDate,
                label: label,
                detail: detail,
                categories: categories,
                isRigMutating: isMutating
            ) else {
                throw JSONRPCError(code: -32603, message: "insert failed", data: nil)
            }
            return .object([
                "id": .string(newID),
                "ok": .bool(true),
                "note": .string("Annotation written. Restart Ephemeris.app (or open the Library window) to see it in the UI."),
            ])
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
                "rigs": .array(rigs.map { r in
                    .object([
                        "name": .string(r.currentName),
                        "mount_class_display": .string(mountClassDisplay(r.mountClass)),
                        "description": .string(rigDescription(r)),
                    ])
                }),
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
