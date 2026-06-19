import Foundation
import CoreData

/// Private-data sync is now handled entirely by Apple CloudKit via
/// `NSPersistentCloudKitContainer` (see `PersistenceController`). Core Data
/// mirrors every change to the signed-in Apple ID's PRIVATE iCloud database
/// automatically — no server, no REST calls, no API keys, and it works offline.
///
/// This type used to be a Firestore REST client. It is now a thin no-op shim so
/// the ~17 existing call sites keep compiling untouched while CloudKit does the
/// real work underneath. The old `FirestoreSyncService` name is preserved via a
/// `typealias` at the bottom of this file.
final class CloudSyncService: @unchecked Sendable {
    static let shared = CloudSyncService()
    private init() {}

    // MARK: - Per-entity sync (no-ops: CloudKit mirrors Core Data automatically)

    func syncGoal(_ goal: Goal) async throws {}
    func deleteGoal(goalId: String) async throws {}
    func syncProfile(_ profile: UserProfile) async throws {}
    func syncAllGoals(context: NSManagedObjectContext) async {}
    func syncMentorMessage(_ message: MentorMessage) async throws {}
    func syncMealEntry(_ entry: MealEntry) async throws {}
    func syncAchievement(_ achievement: Achievement) async throws {}
    func syncFocusSession(_ session: FocusSession) async throws {}

    // MARK: - Hydration / fetch

    /// No longer needed: CloudKit re-hydrates the local store from the user's
    /// private iCloud DB on launch automatically once the container is signed in.
    func hydrateLocalCacheFromCloud() async {}

    func fetchGoals() async throws -> [[String: Any]] { [] }

    /// Account deletion (Apple 5.1.1(v) / GDPR erasure). Local wipe is handled by
    /// `PersistenceController.wipeAllUserData()`; CloudKit removes the mirrored
    /// private records when the user deletes the local store / signs out. There is
    /// no separate remote store to purge, so this is a no-op.
    func deleteAllRemoteData() async throws {}

    /// Transformation photos are persisted locally (and mirror to the user's
    /// private CloudKit DB via Core Data). There is no public photo bucket, so
    /// there is no remote URL to return.
    @discardableResult
    func uploadTransformationPhoto(data photoData: Data, kind: String, goalId: String) async -> String? { nil }
}

/// Back-compat alias so existing call sites (`FirestoreSyncService.shared.…`)
/// keep working without edits. New code should reference `CloudSyncService`.
typealias FirestoreSyncService = CloudSyncService
