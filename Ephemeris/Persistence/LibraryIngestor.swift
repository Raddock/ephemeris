import Foundation
import SwiftData
import CryptoKit

/// Background actor that ingests parsed `GuideLog`s into the SwiftData library store.
/// Per design doc §3.1: ingest holds its own `ModelContext` against the library URL;
/// the document window's `FileDocument` does not share this container.
///
/// Phase 3 deliverable per §10: "Auto-indexing on log open: parse → analyze → persist
/// artifacts via a ModelActor so the document window stays responsive."
@ModelActor
actor LibraryIngestor {

    /// Result of an ingest call.
    struct IngestResult: Sendable {
        let nightRecordId: UUID
        let observationCount: Int
        let didCreate: Bool   // false if the log was already in the store (dedup hit)
    }

    /// Ingest a parsed guide log under the given rig profile.
    /// - Idempotent on `sourceContentHash` (SHA-256 of the raw bytes).
    /// - Always runs the recommender; observations are upserted on every ingest so
    ///   threshold changes propagate without re-importing.
    func ingest(log: GuideLog,
                sourceBytes: Data,
                sourceFilePath: String,
                rigProfile: RigProfile) throws -> IngestResult {
        let contentHash = Self.sha256(of: sourceBytes)
        let nightDate = log.guideSessions.compactMap { $0.startedAt }.min() ?? Date()

        let rigEntity = try findOrCreateRigEntity(matching: rigProfile)
        let (record, didCreate) = try findOrCreateNightRecord(hash: contentHash,
                                                              rigEntity: rigEntity,
                                                              filePath: sourceFilePath,
                                                              nightDate: nightDate)

        // Recompute aggregates and recommender output every time — cheap relative to
        // the full library, and avoids needing migration for threshold changes.
        record.sessionsCount = log.guideSessions.count
        record.totalIntegrationMinutes = log.guideSessions.reduce(0.0) { $0 + $1.duration / 60.0 }

        // Per-session RMS in arcsec — each session is converted with its own pixel
        // scale, so a log whose sessions differ in binning/scale still aggregates
        // correctly. The night-level RMS is the frame-weighted quadrature mean of
        // these; computing it this way (rather than from a single global pixel
        // scale) avoids leaving RMS in pixels when a log mixes scales.
        let perSession: [(rmsArcsec: Double, frames: Int)] = log.guideSessions.map { session in
            let s = SessionStatsCalculator.calculate(session, manualExclusionRanges: [])
            return (s.rmsTotal * session.pixelScale, s.includedFrames)
        }
        let rmsValues = perSession.map(\.rmsArcsec)
        record.bestSessionRMSArcsec = rmsValues.min() ?? 0
        record.worstSessionRMSArcsec = rmsValues.max() ?? 0
        let totalFrames = perSession.reduce(0) { $0 + $1.frames }
        record.medianRMSArcsec = totalFrames > 0
            ? (perSession.reduce(0.0) { $0 + $1.rmsArcsec * $1.rmsArcsec * Double($1.frames) }
               / Double(totalFrames)).squareRoot()
            : 0
        record.lastAnalyzedAt = .now

        // Phase 9: pointing context. Median RA/Dec across the sessions; galactic
        // latitude + Messier catalog match if within tolerance.
        let pointings = log.guideSessions.compactMap { session -> (Double, Double)? in
            let props = session.headerProperties
            guard let ra = props.raHours, let dec = props.decDegrees else { return nil }
            return (ra, dec)
        }
        if !pointings.isEmpty {
            let medRA = Self.circularMedianRAHours(pointings.map { $0.0 })
            let medDec = pointings.map { $0.1 }.sorted()[pointings.count / 2]
            record.medianRAHours = medRA
            record.medianDecDegrees = medDec
            record.galacticLatitudeDeg = Astronomy.galacticLatitude(raHours: medRA, decDegrees: medDec)
            if let target = MessierCatalog.match(raHours: medRA, decDegrees: medDec) {
                record.catalogIdentifier = target.identifier
                record.catalogCommonName = target.commonName
            } else {
                record.catalogIdentifier = nil
                record.catalogCommonName = nil
            }
        }

        try removeExistingObservations(for: record)
        try removeExistingGAResults(for: record)
        try removeExistingSessionRecords(for: record)

        // Per-session detail — one row per GuideSession with header + stats.
        // Sessions are persisted in chronological order so `sessionIndex` is stable.
        let sortedSessions = log.guideSessions
            .enumerated()
            .sorted { (a, b) in
                (a.element.startedAt ?? .distantPast) < (b.element.startedAt ?? .distantPast)
            }
        for (orderIndex, indexed) in sortedSessions.enumerated() {
            let session = indexed.element
            let stats = SessionStatsCalculator.calculate(session, manualExclusionRanges: [])
            let props = session.headerProperties
            let scale = session.pixelScale > 0 ? session.pixelScale : 1.0

            let entity = SessionRecordEntity()
            entity.id = UUID()
            entity.nightRecord = record
            entity.rigProfileId = rigProfile.id
            entity.sessionIndex = orderIndex
            entity.startedAt = session.startedAt
            entity.durationSec = session.duration

            entity.rmsTotalArcsec = stats.rmsTotal * scale
            entity.rmsRAArcsec = stats.rmsRA * scale
            entity.rmsDecArcsec = stats.rmsDec * scale
            entity.peakRAArcsec = stats.peakRA * scale
            entity.peakDecArcsec = stats.peakDec * scale
            entity.driftRAArcsecPerMin = stats.driftRA * scale
            entity.driftDecArcsecPerMin = stats.driftDec * scale
            entity.polarAlignErrorArcmin = stats.polarAlignErrorArcmin ?? 0

            entity.includedFrames = stats.includedFrames
            entity.excludedFrames = stats.excludedFrames
            entity.pixelScale = scale

            entity.raHours = props.raHours
            entity.decDegrees = props.decDegrees
            entity.hourAngleHours = props.hourAngleHours
            entity.altitudeDegrees = props.altitudeDegrees
            entity.azimuthDegrees = props.azimuthDegrees
            entity.pierSide = props.pierSide
            entity.hfdPixels = props.hfdPixels
            entity.exposureMs = props.exposureMs
            entity.multiStarEnabled = props.multiStarEnabled

            modelContext.insert(entity)
        }

        // Parse Guiding Assistant runs from each session's INFO entries and persist
        // them as GAResultEntity records attached to this NightRecord. Picked up by
        // the cross-night GAFreshnessObserver and exposed via the MCP server.
        for session in log.guideSessions {
            for parsed in GAResultParser.parse(session: session) {
                let entity = GAResultEntity()
                entity.id = UUID()
                entity.nightRecord = record
                entity.rigProfileId = rigProfile.id
                entity.runAt = parsed.runAt
                entity.durationSec = parsed.durationSec
                entity.recommendedRAMinMovePx = parsed.recommendedRAMinMovePx
                entity.recommendedDecMinMovePx = parsed.recommendedDecMinMovePx
                entity.recommendedExposureSec = parsed.recommendedExposureSec
                entity.polarAlignErrorArcmin = parsed.polarAlignErrorArcmin
                entity.decBacklashMs = parsed.decBacklashMs
                entity.raPeakToPeakArcsec = parsed.raPeakToPeakArcsec
                entity.raMaxRateOfChangeArcsecPerSec = parsed.raMaxRateOfChangeArcsecPerSec
                entity.highFreqStarMotionArcsecRMS = parsed.highFreqStarMotionArcsecRMS
                entity.rawText = parsed.rawText
                modelContext.insert(entity)
            }
        }
        let observations = RecommenderEngine.default.analyze(log: log, profile: rigProfile)
        for obs in observations {
            let entity = ObservationEntity()
            entity.id = obs.id
            entity.nightRecord = record
            entity.rigProfileId = rigProfile.id
            entity.scopeRaw = obs.scope.rawValue
            entity.categoryRaw = obs.category.rawValue
            entity.severityRaw = obs.severity.rawValue
            entity.sourceAuthorityRaw = obs.sourceAuthority.rawValue
            entity.confidenceRaw = obs.confidence.rawValue
            entity.title = obs.title
            entity.summary = obs.summary
            entity.suggestedResponse = obs.suggestedResponse
            entity.evidenceData = (try? JSONEncoder().encode(obs.evidence)) ?? Data()
            entity.candidateContributorsData = (try? JSONEncoder().encode(obs.candidateContributors)) ?? Data()
            entity.relatedHelpTopicIdsData = (try? JSONEncoder().encode(obs.relatedHelpTopicIds)) ?? Data()
            entity.relatedPHD2ToolsData = (try? JSONEncoder().encode(obs.relatedPHD2Tools.map { $0.rawValue })) ?? Data()
            entity.generatedAt = obs.generatedAt
            entity.dismissedAt = obs.dismissedAt
            modelContext.insert(entity)
        }

        try modelContext.save()

        // Phase 9: re-cluster this rig's nights by pointing. Greedy + idempotent.
        try recomputeTargetClusters(for: rigEntity)
        try modelContext.save()

        // Phase 3: donate to CoreSpotlight so Spotlight surfaces nights & annotations.
        // Best-effort; build a value-type digest first so we don't capture the
        // ModelActor's context in the index callback.
        let digest = makeNightDigest(record: record, rig: rigEntity)
        CoreSpotlightIndexer.donate(night: digest)

        return IngestResult(
            nightRecordId: record.id,
            observationCount: observations.count,
            didCreate: didCreate
        )
    }

    private func makeNightDigest(record: NightRecordEntity, rig: RigProfileEntity) -> NightRecordEntityDigest {
        let dateString = record.nightDate.formatted(date: .abbreviated, time: .omitted)
        var titleParts = [dateString, rig.currentName]
        if record.medianRMSArcsec > 0 {
            titleParts.append(String(format: "%.2f″", record.medianRMSArcsec))
        }
        var subtitleParts: [String] = ["\(record.sessionsCount) sessions"]
        if record.totalIntegrationMinutes > 0 {
            subtitleParts.append(String(format: "%.0f min", record.totalIntegrationMinutes))
        }
        if let catalog = record.catalogIdentifier {
            subtitleParts.append(catalog)
        }
        if let lat = record.galacticLatitudeDeg {
            subtitleParts.append(String(format: "galactic %+.0f°", lat))
        }
        var keywords: [String] = ["Ephemeris", "PHD2", "guide log", rig.currentName]
        if let catalog = record.catalogIdentifier { keywords.append(catalog) }
        if let name = record.catalogCommonName { keywords.append(name) }
        return NightRecordEntityDigest(
            id: record.id,
            title: titleParts.joined(separator: " · "),
            subtitle: subtitleParts.joined(separator: " · "),
            keywords: keywords,
            nightDate: record.nightDate,
            lastAnalyzedAt: record.lastAnalyzedAt
        )
    }

    /// Rebuilds `TargetClusterEntity` rows for a rig from its nights' median pointings.
    /// Idempotent: existing cluster rows for the rig are deleted and re-inserted
    /// each time. Cheap at typical corpus sizes (≤500 nights per rig).
    private func recomputeTargetClusters(for rigEntity: RigProfileEntity) throws {
        let rigID = rigEntity.id
        // Drop old clusters for this rig — cleaner than diff-and-patch and the
        // entity carries no user-facing data the user would notice losing.
        let existingFetch = FetchDescriptor<TargetClusterEntity>(
            predicate: #Predicate { $0.rigProfile?.id == rigID }
        )
        for old in try modelContext.fetch(existingFetch) {
            modelContext.delete(old)
        }

        // Collect every night with a known pointing.
        let nightFetch = FetchDescriptor<NightRecordEntity>(
            predicate: #Predicate { $0.rigProfile?.id == rigID }
        )
        let nights = try modelContext.fetch(nightFetch)
        let points: [TargetClustering.NightPoint] = nights.compactMap { n in
            guard let ra = n.medianRAHours, let dec = n.medianDecDegrees else { return nil }
            return TargetClustering.NightPoint(
                id: n.id,
                raHours: ra,
                decDegrees: dec,
                totalIntegrationMinutes: n.totalIntegrationMinutes,
                medianRMSArcsec: n.medianRMSArcsec
            )
        }
        guard !points.isEmpty else { return }

        var sessionsByNight: [UUID: Int] = [:]
        for n in nights { sessionsByNight[n.id] = n.sessionsCount }

        let clusters = TargetClustering.cluster(
            nights: points,
            rigSessionsByNight: sessionsByNight
        )
        for cluster in clusters {
            let entity = TargetClusterEntity()
            entity.id = cluster.id
            entity.rigProfile = rigEntity
            entity.centerRA = cluster.centerRA
            entity.centerDec = cluster.centerDec
            entity.radiusDeg = cluster.radiusDeg
            entity.catalogMatch = cluster.catalogMatch
            entity.sessionCount = cluster.sessionCount
            entity.totalIntegrationMinutes = cluster.totalIntegrationMinutes
            entity.medianRMSArcsec = cluster.medianRMSArcsec
            entity.nightRecordIdsData = (try? JSONEncoder().encode(cluster.nightIDs.map { $0.uuidString })) ?? Data()
            modelContext.insert(entity)
        }
    }

    /// Look up a `NightRecordEntity` by content hash, or create a new one.
    /// Uniqueness is enforced here rather than via `@Attribute(.unique)` per the
    /// CloudKit-clean rules in §4.
    private func findOrCreateNightRecord(hash: String,
                                         rigEntity: RigProfileEntity,
                                         filePath: String,
                                         nightDate: Date) throws -> (NightRecordEntity, Bool) {
        let fetch = FetchDescriptor<NightRecordEntity>(
            predicate: #Predicate { $0.sourceContentHash == hash }
        )
        if let existing = try modelContext.fetch(fetch).first {
            existing.sourceFilePath = filePath  // refresh in case the file moved
            return (existing, false)
        }
        let record = NightRecordEntity()
        record.id = UUID()
        record.rigProfile = rigEntity
        record.sourceFilePath = filePath
        record.sourceContentHash = hash
        record.nightDate = nightDate
        record.ingestedAt = .now
        modelContext.insert(record)
        return (record, true)
    }

    /// Find a `RigProfileEntity` matching the profile's id, or create a new one from the value.
    private func findOrCreateRigEntity(matching profile: RigProfile) throws -> RigProfileEntity {
        let profileId = profile.id
        let fetch = FetchDescriptor<RigProfileEntity>(
            predicate: #Predicate { $0.id == profileId }
        )
        if let existing = try modelContext.fetch(fetch).first {
            return existing
        }
        let entity = RigProfileEntity(from: profile)
        modelContext.insert(entity)
        return entity
    }

    private func removeExistingObservations(for record: NightRecordEntity) throws {
        let recordId = record.id
        let fetch = FetchDescriptor<ObservationEntity>(
            predicate: #Predicate { $0.nightRecord?.id == recordId }
        )
        let existing = try modelContext.fetch(fetch)
        for obs in existing {
            modelContext.delete(obs)
        }
    }

    private func removeExistingGAResults(for record: NightRecordEntity) throws {
        let recordId = record.id
        let fetch = FetchDescriptor<GAResultEntity>(
            predicate: #Predicate { $0.nightRecord?.id == recordId }
        )
        let existing = try modelContext.fetch(fetch)
        for result in existing {
            modelContext.delete(result)
        }
    }

    private func removeExistingSessionRecords(for record: NightRecordEntity) throws {
        let recordId = record.id
        let fetch = FetchDescriptor<SessionRecordEntity>(
            predicate: #Predicate { $0.nightRecord?.id == recordId }
        )
        let existing = try modelContext.fetch(fetch)
        for sessionRecord in existing {
            modelContext.delete(sessionRecord)
        }
    }

    private static func sha256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Median RA in hours, tolerant of the 0h/24h wrap. When the values span more
    /// than half the circle the cluster straddles 0h; shifting the low half up by
    /// 24h before taking the median keeps the result in a contiguous range.
    private static func circularMedianRAHours(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard let lo = sorted.first, let hi = sorted.last else { return 0 }
        if hi - lo > 12 {
            let unwrapped = values.map { $0 < 12 ? $0 + 24 : $0 }.sorted()
            return unwrapped[unwrapped.count / 2].truncatingRemainder(dividingBy: 24)
        }
        return sorted[sorted.count / 2]
    }
}
