//
//  GuideLogDocument.swift
//  Ephemeris
//
//  Copyright (C) 2026 Andrew Burwell
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI
import UniformTypeIdentifiers

/// Errors a `GuideLogDocument` can throw during open. SwiftUI's `DocumentGroup`
/// renders these via its standard error alert by reading the `LocalizedError`
/// `errorDescription` (alert title) and `recoverySuggestion` (alert body)
/// properties — no custom presentation layer needed.
enum GuideLogLoadError: LocalizedError {
    /// File is not a recognizable PHD2 guide log (text, but wrong content).
    case notPHD2Log
    /// File appears to be a binary blob (PNG, archive, etc.).
    case binaryFile
    /// File exceeds the hard refusal threshold.
    case fileTooLarge(bytes: Int)
    /// File can't be read as UTF-8 / ASCII text.
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notPHD2Log:
            return "This file isn't a PHD2 guide log."
        case .binaryFile:
            return "This file isn't a text file."
        case .fileTooLarge:
            return "This file is too large to load."
        case .unreadable:
            return "This file can't be read."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notPHD2Log:
            return "Ephemeris reads guide log files produced by PHD2 (PHD2_GuideLog_*.txt). The file you opened doesn't appear to be one. Make sure you're opening a .txt file from PHD2's log directory."
        case .binaryFile:
            return "Ephemeris reads PHD2 guide logs, which are plain text. The file you opened appears to be binary."
        case .fileTooLarge(let bytes):
            let mb = Double(bytes) / 1_000_000
            return String(format: "This file is %.0f MB. PHD2 guide logs are typically under 50 MB — loading a file this large could exhaust available memory.", mb)
        case .unreadable:
            return "Ephemeris couldn't read this file as text. It may be using an unusual character encoding. PHD2 guide logs are saved in standard text format (UTF-8 or ASCII)."
        }
    }
}

struct GuideLogDocument: FileDocument {
    /// Hard limits on file size before we refuse to even read it.
    /// PHD2 logs in normal use are well under 50 MB; > 500 MB is almost
    /// certainly an accident or a wrong file.
    private static let maxLoadBytes = 500_000_000

    static var readableContentTypes: [UTType] {
        // Accept the canonical .txt UTI and the .log fallback. The PHD2
        // signature check (`PHD2LogSignature.classify`) is the actual gatekeeper —
        // it runs in `init(configuration:)` and rejects non-PHD2 content
        // regardless of file extension.
        [.plainText, .log, .text]
    }
    static var writableContentTypes: [UTType] { [] }

    let log: GuideLog
    let filename: String?
    /// Original file bytes — retained for v2.0 Phase 3 content-hash dedup.
    /// Nil for synthetic / preview / programmatically-constructed documents.
    let sourceBytes: Data?

    init(log: GuideLog = GuideLog(), filename: String? = nil) {
        self.log = log
        self.filename = filename
        self.sourceBytes = nil
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Empty file: open as an empty document. ContentView's existing
        // "No PHD2 sessions" empty state handles the rest.
        if data.isEmpty {
            self.log = GuideLog()
            self.filename = configuration.file.preferredFilename
            self.sourceBytes = nil
            return
        }

        // Hard refusal at 500 MB — protects against accidentally opening a
        // huge wrong file.
        if data.count > Self.maxLoadBytes {
            throw GuideLogLoadError.fileTooLarge(bytes: data.count)
        }

        // Signature gate runs on the head of the file, before committing to
        // a full parse.
        switch PHD2LogSignature.classify(data) {
        case .binary:
            throw GuideLogLoadError.binaryFile
        case .notPHD2:
            throw GuideLogLoadError.notPHD2Log
        case .confirmed, .likely:
            break
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw GuideLogLoadError.unreadable
        }

        self.log = GuideLogParser.parse(text)
        self.filename = configuration.file.preferredFilename
        self.sourceBytes = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}

extension UTType {
    static var log: UTType {
        UTType(filenameExtension: "log", conformingTo: .plainText) ?? .plainText
    }
}
