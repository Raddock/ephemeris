//
//  LibraryResetTests.swift
//  EphemerisTests
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

import Foundation
import SwiftData
import Testing
@testable import Ephemeris

/// Settings > Reset Log Library data crashed with the Library window open:
/// the reset batch-deleted rows in the store, the window's `@Query` still held
/// the night objects, and the next redraw read a deleted session record. The
/// held night stayed registered in the main context, so nothing told the
/// query it was gone.
@MainActor
struct LibraryResetTests {

    @Test func resetDetachesNightsAnOpenWindowHolds() throws {
        let library = try EphemerisLibrary(inMemory: true)
        let context = library.container.mainContext
        let rig = RigProfileEntity()
        context.insert(rig)
        let night = NightRecordEntity()
        context.insert(night)
        night.rigProfile = rig
        let session = SessionRecordEntity()
        context.insert(session)
        session.nightRecord = night
        let observation = ObservationEntity()
        context.insert(observation)
        observation.nightRecord = night
        try context.save()

        // What the Library window's @Query is holding when the user resets.
        let held = try #require(try context.fetch(FetchDescriptor<NightRecordEntity>()).first)
        let heldID = held.persistentModelID

        try library.resetLibraryData()

        // Detached and unregistered is how SwiftData tells @Query the object is
        // gone. The old batch delete left it registered with its context.
        #expect(held.modelContext == nil)
        #expect((context.registeredModel(for: heldID) as NightRecordEntity?) == nil)

        #expect(try context.fetchCount(FetchDescriptor<NightRecordEntity>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SessionRecordEntity>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ObservationEntity>()) == 0)
        // Rig profiles survive a reset.
        #expect(try context.fetchCount(FetchDescriptor<RigProfileEntity>()) == 1)
    }

    @Test func resetOnAnEmptyLibraryIsHarmless() throws {
        let library = try EphemerisLibrary(inMemory: true)
        try library.resetLibraryData()
        #expect(try library.container.mainContext.fetchCount(FetchDescriptor<NightRecordEntity>()) == 0)
    }
}
