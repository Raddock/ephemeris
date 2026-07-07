import Foundation
import SQLite3

/// Read-only SQLite reader for the Ephemeris library store.
///
/// The app is sandboxed (Developer ID), so SwiftData writes to the container path
/// `~/Library/Containers/com.macobservatory.Ephemeris/Data/Library/Application Support/Ephemeris/Library.store`,
/// not the user's top-level Application Support. The helper opens that file in
/// read-only mode. SwiftData is configured for WAL journaling by default, so
/// concurrent readers don't block the app's writer.
///
/// The schema column names match what the SwiftData @Model macro generates, which
/// follows the convention `Z<UPPERCASE_FIELD_NAME>` in the Core Data backing store.
/// Z_PRIMARYKEY / Z_METADATA are the standard Core Data metadata tables.
final class LibraryStore: @unchecked Sendable {
    private let url: URL
    private var db: OpaquePointer?

    static func defaultStoreURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Containers/com.macobservatory.Ephemeris/Data/Library/Application Support/Ephemeris/Library.store")
    }

    init(url: URL) {
        self.url = url
    }

    func openIfNeeded() -> Bool {
        if db != nil { return true }
        guard FileManager.default.fileExists(atPath: url.path) else {
            FileHandle.standardError.write(
                "Library store not found at \(url.path) — open the app at least once to create it.\n"
                    .data(using: .utf8)!
            )
            return false
        }
        // SQLITE_OPEN_READONLY plus SQLITE_OPEN_NOMUTEX since we serialize access from the
        // single-threaded MCP server loop.
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(url.path, &db, flags, nil)
        guard result == SQLITE_OK else {
            FileHandle.standardError.write(
                "sqlite3_open_v2 failed: \(result)\n".data(using: .utf8)!
            )
            db = nil
            return false
        }
        return true
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Rigs

    struct RigRow: Sendable {
        let uuid: String
        let currentName: String
        let mountClass: String
        let hasHighPrecisionEncoders: Bool
        let imagingFocalLengthMm: Double
        let imagingPixelSizeMicrons: Double
        let imagingBinning: Int
        /// Focal reducer / flattener factor (< 1 shortens effective focal length).
        /// nil means "not set" and is treated as 1.0 in scale math, matching
        /// `ImagingScale.compute` in the app.
        let reducerFactor: Double?
        let mountModel: String?
        let notes: String?
    }

    func rig(uuid: String) -> RigRow? {
        guard openIfNeeded(), let db else { return nil }
        let sql = """
        SELECT ZID, ZCURRENTNAME, ZMOUNTCLASSRAW, ZHASHIGHPRECISIONENCODERS,
               ZIMAGINGFOCALLENGTHMM, ZIMAGINGPIXELSIZEMICRONS, ZIMAGINGBINNING,
               ZREDUCERFACTOR, ZMOUNTMODEL, ZNOTES
          FROM ZRIGPROFILEENTITY
         WHERE ZID = ?
         LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard bindUUID(stmt, idx: 1, uuid: uuid) else { return nil }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readRigRow(stmt)
    }

    private func readRigRow(_ stmt: OpaquePointer?) -> RigRow {
        RigRow(
            uuid: readUUID(stmt, col: 0) ?? "",
            currentName: readString(stmt, col: 1) ?? "",
            mountClass: readString(stmt, col: 2) ?? "",
            hasHighPrecisionEncoders: sqlite3_column_int(stmt, 3) != 0,
            imagingFocalLengthMm: sqlite3_column_double(stmt, 4),
            imagingPixelSizeMicrons: sqlite3_column_double(stmt, 5),
            imagingBinning: Int(sqlite3_column_int(stmt, 6)),
            reducerFactor: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 7),
            mountModel: readString(stmt, col: 8),
            notes: readString(stmt, col: 9)
        )
    }

    func listRigs() -> [RigRow] {
        guard openIfNeeded(), let db else { return [] }
        let sql = """
        SELECT ZID, ZCURRENTNAME, ZMOUNTCLASSRAW, ZHASHIGHPRECISIONENCODERS,
               ZIMAGINGFOCALLENGTHMM, ZIMAGINGPIXELSIZEMICRONS, ZIMAGINGBINNING,
               ZREDUCERFACTOR, ZMOUNTMODEL, ZNOTES
          FROM ZRIGPROFILEENTITY
         ORDER BY ZCURRENTNAME
        """
        var rows: [RigRow] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(readRigRow(stmt))
        }
        return rows
    }

    // MARK: - Nights

    struct NightRow: Sendable {
        let uuid: String
        let rigUUID: String
        let nightDate: Date
        let sessionsCount: Int
        let totalIntegrationMinutes: Double
        let medianRMSArcsec: Double
        let bestSessionRMSArcsec: Double
        let worstSessionRMSArcsec: Double
        let sourceFilePath: String
        let subQualityRaw: String?
        let medianRAHours: Double?
        let medianDecDegrees: Double?
        let galacticLatitudeDeg: Double?
        let catalogIdentifier: String?
        let catalogCommonName: String?
    }

    /// Fetch a single night by UUID. Returns the full pointing/target context plus rollups.
    func night(uuid: String) -> NightRow? {
        guard openIfNeeded(), let db else { return nil }
        let sql = """
        SELECT n.ZID, r.ZID, n.ZNIGHTDATE, n.ZSESSIONSCOUNT,
               n.ZTOTALINTEGRATIONMINUTES, n.ZMEDIANRMSARCSEC,
               n.ZBESTSESSIONRMSARCSEC, n.ZWORSTSESSIONRMSARCSEC,
               n.ZSOURCEFILEPATH, n.ZSUBQUALITYRAW,
               n.ZMEDIANRAHOURS, n.ZMEDIANDECDEGREES, n.ZGALACTICLATITUDEDEG,
               n.ZCATALOGIDENTIFIER, n.ZCATALOGCOMMONNAME
          FROM ZNIGHTRECORDENTITY n
          LEFT JOIN ZRIGPROFILEENTITY r ON n.ZRIGPROFILE = r.Z_PK
         WHERE n.ZID = ?
         LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard bindUUID(stmt, idx: 1, uuid: uuid) else { return nil }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readNightRow(stmt)
    }

    private func readNightRow(_ stmt: OpaquePointer?) -> NightRow {
        let rawNightDate = sqlite3_column_double(stmt, 2)
        return NightRow(
            uuid: readUUID(stmt, col: 0) ?? "",
            rigUUID: readUUID(stmt, col: 1) ?? "",
            nightDate: Date(timeIntervalSinceReferenceDate: rawNightDate),
            sessionsCount: Int(sqlite3_column_int(stmt, 3)),
            totalIntegrationMinutes: sqlite3_column_double(stmt, 4),
            medianRMSArcsec: sqlite3_column_double(stmt, 5),
            bestSessionRMSArcsec: sqlite3_column_double(stmt, 6),
            worstSessionRMSArcsec: sqlite3_column_double(stmt, 7),
            sourceFilePath: readString(stmt, col: 8) ?? "",
            subQualityRaw: readString(stmt, col: 9),
            medianRAHours: sqlite3_column_type(stmt, 10) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 10),
            medianDecDegrees: sqlite3_column_type(stmt, 11) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 11),
            galacticLatitudeDeg: sqlite3_column_type(stmt, 12) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 12),
            catalogIdentifier: readString(stmt, col: 13),
            catalogCommonName: readString(stmt, col: 14)
        )
    }

    func listNights(rigUUID: String? = nil, sinceDays: Int? = nil, limit: Int = 100) -> [NightRow] {
        guard openIfNeeded(), let db else { return [] }
        var sql = """
        SELECT n.ZID, r.ZID, n.ZNIGHTDATE, n.ZSESSIONSCOUNT,
               n.ZTOTALINTEGRATIONMINUTES, n.ZMEDIANRMSARCSEC,
               n.ZBESTSESSIONRMSARCSEC, n.ZWORSTSESSIONRMSARCSEC,
               n.ZSOURCEFILEPATH, n.ZSUBQUALITYRAW,
               n.ZMEDIANRAHOURS, n.ZMEDIANDECDEGREES, n.ZGALACTICLATITUDEDEG,
               n.ZCATALOGIDENTIFIER, n.ZCATALOGCOMMONNAME
          FROM ZNIGHTRECORDENTITY n
          LEFT JOIN ZRIGPROFILEENTITY r ON n.ZRIGPROFILE = r.Z_PK
         WHERE 1=1
        """
        if rigUUID != nil { sql += " AND r.ZID = ?" }
        if sinceDays != nil { sql += " AND n.ZNIGHTDATE >= ?" }
        sql += " ORDER BY n.ZNIGHTDATE DESC LIMIT ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var bindIdx: Int32 = 1
        if let rigUUID {
            _ = bindUUID(stmt, idx: bindIdx, uuid: rigUUID)
            bindIdx += 1
        }
        if let days = sinceDays {
            // Core Data stores dates as seconds since 2001-01-01.
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            sqlite3_bind_double(stmt, bindIdx, cutoff.timeIntervalSinceReferenceDate)
            bindIdx += 1
        }
        sqlite3_bind_int(stmt, bindIdx, Int32(max(1, min(limit, 10_000))))
        var rows: [NightRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(readNightRow(stmt))
        }
        return rows
    }

    // MARK: - Sessions

    struct SessionRow: Sendable {
        let uuid: String
        let nightUUID: String
        let sessionIndex: Int
        let startedAt: Date?
        let durationSec: Double
        let rmsTotalArcsec: Double
        let rmsRAArcsec: Double
        let rmsDecArcsec: Double
        let peakRAArcsec: Double
        let peakDecArcsec: Double
        let driftRAArcsecPerMin: Double
        let driftDecArcsecPerMin: Double
        let polarAlignErrorArcmin: Double
        let includedFrames: Int
        let excludedFrames: Int
        let pixelScale: Double
        let raHours: Double?
        let decDegrees: Double?
        let hourAngleHours: Double?
        let altitudeDegrees: Double?
        let azimuthDegrees: Double?
        let pierSide: String?
        let hfdPixels: Double?
        let exposureMs: Int?
        let multiStarEnabled: Bool
    }

    func listSessions(nightUUID: String? = nil, rigUUID: String? = nil, limit: Int = 1_000) -> [SessionRow] {
        guard openIfNeeded(), let db else { return [] }
        var sql = """
        SELECT s.ZID, n.ZID, s.ZSESSIONINDEX, s.ZSTARTEDAT, s.ZDURATIONSEC,
               s.ZRMSTOTALARCSEC, s.ZRMSRAARCSEC, s.ZRMSDECARCSEC,
               s.ZPEAKRAARCSEC, s.ZPEAKDECARCSEC,
               s.ZDRIFTRAARCSECPERMIN, s.ZDRIFTDECARCSECPERMIN,
               s.ZPOLARALIGNERRORARCMIN,
               s.ZINCLUDEDFRAMES, s.ZEXCLUDEDFRAMES, s.ZPIXELSCALE,
               s.ZRAHOURS, s.ZDECDEGREES, s.ZHOURANGLEHOURS,
               s.ZALTITUDEDEGREES, s.ZAZIMUTHDEGREES,
               s.ZPIERSIDE, s.ZHFDPIXELS, s.ZEXPOSUREMS, s.ZMULTISTARENABLED
          FROM ZSESSIONRECORDENTITY s
          LEFT JOIN ZNIGHTRECORDENTITY n ON s.ZNIGHTRECORD = n.Z_PK
         WHERE 1=1
        """
        if nightUUID != nil { sql += " AND n.ZID = ?" }
        if rigUUID != nil { sql += " AND s.ZRIGPROFILEID = ?" }
        sql += " ORDER BY s.ZSTARTEDAT ASC LIMIT \(limit)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var bindIdx: Int32 = 1
        if let nightUUID {
            _ = bindUUID(stmt, idx: bindIdx, uuid: nightUUID)
            bindIdx += 1
        }
        if let rigUUID {
            _ = bindUUID(stmt, idx: bindIdx, uuid: rigUUID)
            bindIdx += 1
        }

        var rows: [SessionRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let startedAtRaw = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 3)
            rows.append(SessionRow(
                uuid: readUUID(stmt, col: 0) ?? "",
                nightUUID: readUUID(stmt, col: 1) ?? "",
                sessionIndex: Int(sqlite3_column_int(stmt, 2)),
                startedAt: startedAtRaw.map { Date(timeIntervalSinceReferenceDate: $0) },
                durationSec: sqlite3_column_double(stmt, 4),
                rmsTotalArcsec: sqlite3_column_double(stmt, 5),
                rmsRAArcsec: sqlite3_column_double(stmt, 6),
                rmsDecArcsec: sqlite3_column_double(stmt, 7),
                peakRAArcsec: sqlite3_column_double(stmt, 8),
                peakDecArcsec: sqlite3_column_double(stmt, 9),
                driftRAArcsecPerMin: sqlite3_column_double(stmt, 10),
                driftDecArcsecPerMin: sqlite3_column_double(stmt, 11),
                polarAlignErrorArcmin: sqlite3_column_double(stmt, 12),
                includedFrames: Int(sqlite3_column_int(stmt, 13)),
                excludedFrames: Int(sqlite3_column_int(stmt, 14)),
                pixelScale: sqlite3_column_double(stmt, 15),
                raHours: sqlite3_column_type(stmt, 16) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 16),
                decDegrees: sqlite3_column_type(stmt, 17) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 17),
                hourAngleHours: sqlite3_column_type(stmt, 18) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 18),
                altitudeDegrees: sqlite3_column_type(stmt, 19) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 19),
                azimuthDegrees: sqlite3_column_type(stmt, 20) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 20),
                pierSide: readString(stmt, col: 21),
                hfdPixels: sqlite3_column_type(stmt, 22) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 22),
                exposureMs: sqlite3_column_type(stmt, 23) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 23)),
                multiStarEnabled: sqlite3_column_int(stmt, 24) != 0
            ))
        }
        return rows
    }

    // MARK: - Observations

    struct ObservationRow: Sendable {
        let uuid: String
        /// nil when the observation isn't linked to a night (cross-night observations).
        let nightUUID: String?
        let title: String
        let summary: String
        let suggestedResponse: String
        let categoryRaw: Int
        let severityRaw: Int
        let sourceAuthority: String
        let confidence: String
        let generatedAt: Date
    }

    func listObservations(rigUUID: String? = nil, limit: Int = 200) -> [ObservationRow] {
        guard openIfNeeded(), let db else { return [] }
        var sql = """
        SELECT o.ZID, n.ZID, o.ZTITLE, o.ZSUMMARY, o.ZSUGGESTEDRESPONSE,
               o.ZCATEGORYRAW, o.ZSEVERITYRAW, o.ZSOURCEAUTHORITYRAW,
               o.ZCONFIDENCERAW, o.ZGENERATEDAT
          FROM ZOBSERVATIONENTITY o
          LEFT JOIN ZNIGHTRECORDENTITY n ON o.ZNIGHTRECORD = n.Z_PK
        """
        if let rigUUID {
            sql += " WHERE o.ZRIGPROFILEID = ?"
            _ = rigUUID
        }
        sql += " ORDER BY o.ZSEVERITYRAW DESC, o.ZGENERATEDAT DESC LIMIT \(limit)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if let rigUUID {
            _ = bindUUID(stmt, idx: 1, uuid: rigUUID)
        }
        var rows: [ObservationRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(ObservationRow(
                uuid: readUUID(stmt, col: 0) ?? "",
                nightUUID: readUUID(stmt, col: 1),
                title: readString(stmt, col: 2) ?? "",
                summary: readString(stmt, col: 3) ?? "",
                suggestedResponse: readString(stmt, col: 4) ?? "",
                categoryRaw: Int(sqlite3_column_int(stmt, 5)),
                severityRaw: Int(sqlite3_column_int(stmt, 6)),
                sourceAuthority: readString(stmt, col: 7) ?? "",
                confidence: readString(stmt, col: 8) ?? "",
                generatedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 9))
            ))
        }
        return rows
    }

    // MARK: - Observation by ID

    func observation(uuid: String) -> ObservationRow? {
        guard openIfNeeded(), let db else { return nil }
        let sql = """
        SELECT o.ZID, n.ZID, o.ZTITLE, o.ZSUMMARY, o.ZSUGGESTEDRESPONSE,
               o.ZCATEGORYRAW, o.ZSEVERITYRAW, o.ZSOURCEAUTHORITYRAW,
               o.ZCONFIDENCERAW, o.ZGENERATEDAT
          FROM ZOBSERVATIONENTITY o
          LEFT JOIN ZNIGHTRECORDENTITY n ON o.ZNIGHTRECORD = n.Z_PK
         WHERE o.ZID = ?
         LIMIT 1
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard bindUUID(stmt, idx: 1, uuid: uuid) else { return nil }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return ObservationRow(
            uuid: readUUID(stmt, col: 0) ?? "",
            nightUUID: readUUID(stmt, col: 1),
            title: readString(stmt, col: 2) ?? "",
            summary: readString(stmt, col: 3) ?? "",
            suggestedResponse: readString(stmt, col: 4) ?? "",
            categoryRaw: Int(sqlite3_column_int(stmt, 5)),
            severityRaw: Int(sqlite3_column_int(stmt, 6)),
            sourceAuthority: readString(stmt, col: 7) ?? "",
            confidence: readString(stmt, col: 8) ?? "",
            generatedAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 9))
        )
    }

    // MARK: - Annotations

    struct AnnotationRow: Sendable {
        let uuid: String
        let nightUUID: String?
        let rigProfileId: String
        let eventDate: Date
        let label: String
        let detail: String
        let isRigMutating: Bool
        let categories: [String]
        let createdAt: Date
    }

    func listAnnotations(rigUUID: String? = nil, nightUUID: String? = nil, limit: Int = 200) -> [AnnotationRow] {
        guard openIfNeeded(), let db else { return [] }
        var sql = """
        SELECT a.ZID, n.ZID, a.ZRIGPROFILEID, a.ZEVENTDATE, a.ZLABEL,
               a.ZDETAIL, a.ZISRIGMUTATING, a.ZCATEGORIESDATA, a.ZCREATEDAT
          FROM ZANNOTATIONENTITY a
          LEFT JOIN ZNIGHTRECORDENTITY n ON a.ZNIGHTRECORD = n.Z_PK
         WHERE 1=1
        """
        if nightUUID != nil { sql += " AND n.ZID = ?" }
        if rigUUID != nil { sql += " AND a.ZRIGPROFILEID = ?" }
        sql += " ORDER BY a.ZEVENTDATE DESC LIMIT \(limit)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var bindIdx: Int32 = 1
        if let nightUUID {
            _ = bindUUID(stmt, idx: bindIdx, uuid: nightUUID)
            bindIdx += 1
        }
        if let rigUUID {
            _ = bindUUID(stmt, idx: bindIdx, uuid: rigUUID)
            bindIdx += 1
        }

        var rows: [AnnotationRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var categories: [String] = []
            if sqlite3_column_type(stmt, 7) == SQLITE_BLOB,
               let raw = sqlite3_column_blob(stmt, 7) {
                let length = Int(sqlite3_column_bytes(stmt, 7))
                let data = Data(bytes: raw, count: length)
                if let arr = try? JSONDecoder().decode([String].self, from: data) {
                    categories = arr
                }
            }
            rows.append(AnnotationRow(
                uuid: readUUID(stmt, col: 0) ?? "",
                nightUUID: readUUID(stmt, col: 1),
                rigProfileId: readUUID(stmt, col: 2) ?? "",
                eventDate: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 3)),
                label: readString(stmt, col: 4) ?? "",
                detail: readString(stmt, col: 5) ?? "",
                isRigMutating: sqlite3_column_int(stmt, 6) != 0,
                categories: categories,
                createdAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 8))
            ))
        }
        return rows
    }

    // MARK: - GA Results

    struct GAResultRow: Sendable {
        let uuid: String
        let nightUUID: String?
        let rigProfileId: String
        let runAt: Date
        let durationSec: Int
        let recommendedRAMinMovePx: Double?
        let recommendedDecMinMovePx: Double?
        let recommendedExposureSec: Double?
        let polarAlignErrorArcmin: Double?
        let decBacklashMs: Double?
        let raPeakToPeakArcsec: Double?
        let raMaxRateOfChangeArcsecPerSec: Double?
        let highFreqStarMotionArcsecRMS: Double?
        let rawText: String
    }

    func listGAResults(rigUUID: String? = nil, nightUUID: String? = nil, limit: Int = 200) -> [GAResultRow] {
        guard openIfNeeded(), let db else { return [] }
        var sql = """
        SELECT g.ZID, n.ZID, g.ZRIGPROFILEID, g.ZRUNAT, g.ZDURATIONSEC,
               g.ZRECOMMENDEDRAMINMOVEPX, g.ZRECOMMENDEDDECMINMOVEPX,
               g.ZRECOMMENDEDEXPOSURESEC, g.ZPOLARALIGNERRORARCMIN,
               g.ZDECBACKLASHMS, g.ZRAPEAKTOPEAKARCSEC,
               g.ZRAMAXRATEOFCHANGEARCSECPERSEC, g.ZHIGHFREQSTARMOTIONARCSECRMS,
               g.ZRAWTEXT
          FROM ZGARESULTENTITY g
          LEFT JOIN ZNIGHTRECORDENTITY n ON g.ZNIGHTRECORD = n.Z_PK
         WHERE 1=1
        """
        if nightUUID != nil { sql += " AND n.ZID = ?" }
        if rigUUID != nil { sql += " AND g.ZRIGPROFILEID = ?" }
        sql += " ORDER BY g.ZRUNAT DESC LIMIT \(limit)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var bindIdx: Int32 = 1
        if let nightUUID {
            _ = bindUUID(stmt, idx: bindIdx, uuid: nightUUID)
            bindIdx += 1
        }
        if let rigUUID {
            _ = bindUUID(stmt, idx: bindIdx, uuid: rigUUID)
            bindIdx += 1
        }
        var rows: [GAResultRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func optDouble(_ col: Int32) -> Double? {
                sqlite3_column_type(stmt, col) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, col)
            }
            rows.append(GAResultRow(
                uuid: readUUID(stmt, col: 0) ?? "",
                nightUUID: readUUID(stmt, col: 1),
                rigProfileId: readUUID(stmt, col: 2) ?? "",
                runAt: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 3)),
                durationSec: Int(sqlite3_column_int(stmt, 4)),
                recommendedRAMinMovePx: optDouble(5),
                recommendedDecMinMovePx: optDouble(6),
                recommendedExposureSec: optDouble(7),
                polarAlignErrorArcmin: optDouble(8),
                decBacklashMs: optDouble(9),
                raPeakToPeakArcsec: optDouble(10),
                raMaxRateOfChangeArcsecPerSec: optDouble(11),
                highFreqStarMotionArcsecRMS: optDouble(12),
                rawText: readString(stmt, col: 13) ?? ""
            ))
        }
        return rows
    }

    // MARK: - Target Clusters

    struct TargetRow: Sendable {
        let uuid: String
        let rigUUID: String
        let centerRA: Double
        let centerDec: Double
        let radiusDeg: Double
        let catalogMatch: String?
        let sessionCount: Int
        let totalIntegrationMinutes: Double
        let medianRMSArcsec: Double
        let nightRecordIds: [String]
    }

    func listTargets(rigUUID: String? = nil, limit: Int = 100) -> [TargetRow] {
        guard openIfNeeded(), let db else { return [] }
        var sql = """
        SELECT t.ZID, r.ZID, t.ZCENTERRA, t.ZCENTERDEC, t.ZRADIUSDEG,
               t.ZCATALOGMATCH, t.ZSESSIONCOUNT, t.ZTOTALINTEGRATIONMINUTES,
               t.ZMEDIANRMSARCSEC, t.ZNIGHTRECORDIDSDATA
          FROM ZTARGETCLUSTERENTITY t
          LEFT JOIN ZRIGPROFILEENTITY r ON t.ZRIGPROFILE = r.Z_PK
         WHERE 1=1
        """
        if rigUUID != nil { sql += " AND r.ZID = ?" }
        sql += " ORDER BY t.ZTOTALINTEGRATIONMINUTES DESC LIMIT \(limit)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if let rigUUID {
            _ = bindUUID(stmt, idx: 1, uuid: rigUUID)
        }
        var rows: [TargetRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var nightIds: [String] = []
            if sqlite3_column_type(stmt, 9) == SQLITE_BLOB,
               let raw = sqlite3_column_blob(stmt, 9) {
                let length = Int(sqlite3_column_bytes(stmt, 9))
                let data = Data(bytes: raw, count: length)
                if let arr = try? JSONDecoder().decode([String].self, from: data) {
                    nightIds = arr
                }
            }
            rows.append(TargetRow(
                uuid: readUUID(stmt, col: 0) ?? "",
                rigUUID: readUUID(stmt, col: 1) ?? "",
                centerRA: sqlite3_column_double(stmt, 2),
                centerDec: sqlite3_column_double(stmt, 3),
                radiusDeg: sqlite3_column_double(stmt, 4),
                catalogMatch: readString(stmt, col: 5),
                sessionCount: Int(sqlite3_column_int(stmt, 6)),
                totalIntegrationMinutes: sqlite3_column_double(stmt, 7),
                medianRMSArcsec: sqlite3_column_double(stmt, 8),
                nightRecordIds: nightIds
            ))
        }
        return rows
    }

    // MARK: - Helpers

    private func readString(_ stmt: OpaquePointer?, col: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: cString)
    }

    /// Bind a UUID-string filter value as the 16-byte BLOB that SwiftData expects.
    /// Without this, filtering on `WHERE ZID = ?` against a BLOB column with a text
    /// parameter silently returns zero rows. SQLite stores the destructor pointer
    /// after the call, so we use SQLITE_TRANSIENT to have SQLite copy the bytes.
    private func bindUUID(_ stmt: OpaquePointer?, idx: Int32, uuid: String) -> Bool {
        guard let parsed = UUID(uuidString: uuid) else { return false }
        var bytes = parsed.uuid
        return withUnsafePointer(to: &bytes) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: 16) { raw in
                sqlite3_bind_blob(stmt, idx, raw, 16, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK
            }
        }
    }

    /// SwiftData stores UUID attributes as 16-byte BLOBs in SQLite, not TEXT.
    /// Reading them via `sqlite3_column_text` returns garbled bytes — this helper
    /// pulls the raw 16-byte BLOB and formats it as a canonical UUID string.
    /// Falls back to the text reader for legacy stores that stored UUIDs as text.
    private func readUUID(_ stmt: OpaquePointer?, col: Int32) -> String? {
        let type = sqlite3_column_type(stmt, col)
        if type == SQLITE_BLOB {
            let length = Int(sqlite3_column_bytes(stmt, col))
            guard length == 16, let raw = sqlite3_column_blob(stmt, col) else {
                return nil
            }
            let bytes = raw.assumingMemoryBound(to: UInt8.self)
            let tuple: uuid_t = (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            )
            return UUID(uuid: tuple).uuidString
        }
        return readString(stmt, col: col)
    }
}
