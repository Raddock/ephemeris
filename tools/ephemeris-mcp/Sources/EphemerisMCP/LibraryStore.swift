import Foundation
import SQLite3

/// Read-only SQLite reader for the Ephemeris library store.
///
/// The app uses SwiftData which writes to a SQLite file at
/// `~/Library/Application Support/Ephemeris/Library.store`. The helper opens that
/// same file in read-only mode. SwiftData is configured for WAL journaling by default,
/// so concurrent readers don't block the app's writer.
///
/// The schema column names match what the SwiftData @Model macro generates, which
/// follows the convention `Z<UPPERCASE_FIELD_NAME>` in the Core Data backing store.
/// Z_PRIMARYKEY / Z_METADATA are the standard Core Data metadata tables.
final class LibraryStore: @unchecked Sendable {
    private let url: URL
    private var db: OpaquePointer?

    static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("Ephemeris", isDirectory: true)
            .appendingPathComponent("Library.store")
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
        let mountModel: String?
        let notes: String?
    }

    func listRigs() -> [RigRow] {
        guard openIfNeeded(), let db else { return [] }
        let sql = """
        SELECT ZID, ZCURRENTNAME, ZMOUNTCLASSRAW, ZHASHIGHPRECISIONENCODERS,
               ZIMAGINGFOCALLENGTHMM, ZIMAGINGPIXELSIZEMICRONS, ZIMAGINGBINNING,
               ZMOUNTMODEL, ZNOTES
          FROM ZRIGPROFILEENTITY
         ORDER BY ZCURRENTNAME
        """
        var rows: [RigRow] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(RigRow(
                uuid: readString(stmt, col: 0) ?? "",
                currentName: readString(stmt, col: 1) ?? "",
                mountClass: readString(stmt, col: 2) ?? "",
                hasHighPrecisionEncoders: sqlite3_column_int(stmt, 3) != 0,
                imagingFocalLengthMm: sqlite3_column_double(stmt, 4),
                imagingPixelSizeMicrons: sqlite3_column_double(stmt, 5),
                imagingBinning: Int(sqlite3_column_int(stmt, 6)),
                mountModel: readString(stmt, col: 7),
                notes: readString(stmt, col: 8)
            ))
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
    }

    func listNights(rigUUID: String? = nil, sinceDays: Int? = nil, limit: Int = 100) -> [NightRow] {
        guard openIfNeeded(), let db else { return [] }
        var sql = """
        SELECT n.ZID, r.ZID, n.ZNIGHTDATE, n.ZSESSIONSCOUNT,
               n.ZTOTALINTEGRATIONMINUTES, n.ZMEDIANRMSARCSEC,
               n.ZBESTSESSIONRMSARCSEC, n.ZWORSTSESSIONRMSARCSEC,
               n.ZSOURCEFILEPATH
          FROM ZNIGHTRECORDENTITY n
          LEFT JOIN ZRIGPROFILEENTITY r ON n.ZRIGPROFILE = r.Z_PK
         WHERE 1=1
        """
        if rigUUID != nil { sql += " AND r.ZID = ?" }
        if let days = sinceDays {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            // Core Data stores dates as seconds since 2001-01-01
            let coreDataCutoff = cutoff.timeIntervalSinceReferenceDate
            sql += " AND n.ZNIGHTDATE >= \(coreDataCutoff)"
        }
        sql += " ORDER BY n.ZNIGHTDATE DESC LIMIT \(limit)"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var bindIdx: Int32 = 1
        if let rigUUID {
            sqlite3_bind_text(stmt, bindIdx, rigUUID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            bindIdx += 1
        }
        var rows: [NightRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rawNightDate = sqlite3_column_double(stmt, 2)
            rows.append(NightRow(
                uuid: readString(stmt, col: 0) ?? "",
                rigUUID: readString(stmt, col: 1) ?? "",
                nightDate: Date(timeIntervalSinceReferenceDate: rawNightDate),
                sessionsCount: Int(sqlite3_column_int(stmt, 3)),
                totalIntegrationMinutes: sqlite3_column_double(stmt, 4),
                medianRMSArcsec: sqlite3_column_double(stmt, 5),
                bestSessionRMSArcsec: sqlite3_column_double(stmt, 6),
                worstSessionRMSArcsec: sqlite3_column_double(stmt, 7),
                sourceFilePath: readString(stmt, col: 8) ?? ""
            ))
        }
        return rows
    }

    // MARK: - Observations

    struct ObservationRow: Sendable {
        let uuid: String
        let nightUUID: String
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
            sqlite3_bind_text(stmt, 1, rigUUID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        var rows: [ObservationRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(ObservationRow(
                uuid: readString(stmt, col: 0) ?? "",
                nightUUID: readString(stmt, col: 1) ?? "",
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

    // MARK: - Helpers

    private func readString(_ stmt: OpaquePointer?, col: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: cString)
    }
}
