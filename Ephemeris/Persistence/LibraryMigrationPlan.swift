import Foundation
import SwiftData

/// Migration plan for the library store. Registered from day one so the first
/// real schema change (SchemaV2) has a home and existing users' libraries keep
/// opening — shipping a schema change with no plan means their store fails to
/// load.
///
/// When SchemaV2 lands:
/// 1. Add `SchemaV2.self` to `schemas`.
/// 2. Add a stage: `.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)`
///    for additive changes, or `.custom(...)` with will/didMigrate handlers when
///    data must be transformed (e.g. renaming `medianRMSArcsec` to
///    `nightRMSArcsec`, which is already queued for V2 — see SchemaV1's comment).
enum LibraryMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
