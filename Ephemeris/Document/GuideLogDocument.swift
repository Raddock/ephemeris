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

struct GuideLogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .log, .text] }
    static var writableContentTypes: [UTType] { [] }

    let log: GuideLog
    let filename: String?

    init(log: GuideLog = GuideLog(), filename: String? = nil) {
        self.log = log
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let text = String(decoding: data, as: UTF8.self)
        self.log = GuideLogParser.parse(text)
        self.filename = configuration.file.preferredFilename
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}

extension UTType {
    static var log: UTType { UTType(filenameExtension: "log", conformingTo: .plainText) ?? .plainText }
}
