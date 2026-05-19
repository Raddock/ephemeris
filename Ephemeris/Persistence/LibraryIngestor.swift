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
        let aggregate = LogAggregateStatsCalculator.calculate(log)
        record.sessionsCount = log.guideSessions.count
        record.totalIntegrationMinutes = log.guideSessions.reduce(0.0) { $0 + $1.duration / 60.0 }
        record.medianRMSArcsec = aggregate.weightedRMSTotal * (aggregate.pixelScale > 0 ? aggregate.pixelScale : 1.0)

        // best/worst session RMS in arcsec
        let perSession = log.guideSessions.map { session in
            let s = SessionStatsCalculator.calculate(session, manualExclusionRanges: [])
            return s.rmsTotal * session.pixelScale
        }
        record.bestSessionRMSArcsec = perSession.min() ?? 0
        record.worstSessionRMSArcsec = perSession.max() ?? 0
        record.lastAnalyzedAt = .now

        // Phase 9: pointing context. Median RA/Dec across the sessions; galactic
        // latitude + Messier catalog match if within tolerance.
        let pointings = log.guideSessions.compactMap { session -> (Double, Double)? in
            let props = session.headerProperties
            guard let ra = props.raHours, let dec = props.decDegrees else { return nil }
            return (ra, dec)
        }
        if !pointings.isEmpty {
            let medRA = pointings.map { $0.0 }.sorted()[pointings.count / 2]
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

        return IngestResult(
            nightRecordId: record.id,
            observationCount: observations.count,
            didCreate: didCreate
        )
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

    private static func sha256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
