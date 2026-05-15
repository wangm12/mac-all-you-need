import Foundation
import GRDB

// DEPRECATED COMPILE SHIM. The `app_profiles` table was dropped in migration
// 005-personalization. This file remains only so VoiceCoordinator and
// AppController keep compiling until T7 removes the last call sites. All
// SQL methods are no-ops — fetch returns nil, list returns [], upsert
// returns a synthetic record, delete does nothing. This keeps intermediate
// dictation from crashing on a missing table while T7 lands.

public final class VoiceAppProfileStore: @unchecked Sendable {
    private let db: Database

    public init(database: Database) {
        db = database
    }

    @discardableResult
    public func upsert(
        bundleID: String,
        displayName: String,
        config: VoiceAppProfileConfig
    ) throws -> VoiceAppProfile {
        // No-op: app_profiles was dropped in migration 005. Returns a synthetic
        // record so any caller awaiting a return value sees a benign value.
        VoiceAppProfile(
            id: UUID().uuidString,
            bundleID: bundleID,
            displayName: displayName.isEmpty ? bundleID : displayName,
            config: config,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    public func fetch(bundleID _: String) throws -> VoiceAppProfile? {
        // Table was dropped — there is nothing to fetch.
        nil
    }

    public func list() throws -> [VoiceAppProfile] {
        // Table was dropped — nothing to list.
        []
    }

    public func delete(id _: String) throws {
        // No-op: nothing to delete from a dropped table.
    }
}

public enum VoiceAppProfileStoreError: Error, Equatable {
    case emptyBundleID
    case invalidJSON
}
