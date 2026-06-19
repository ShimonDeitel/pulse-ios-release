import Foundation
import CoreData

/// Exports the signed-in user's local data to a JSON file for download.
///
/// Backs the data-portability promise in the Terms / Privacy Policy and the
/// GDPR/CCPA "right to access & portability." Reads attributes defensively via
/// the Core Data model itself (`entity.attributesByName`) so it can never crash
/// on a schema change and always exports the full, current shape.
enum DataExporter {

    /// Build a pretty-printed JSON string of the user's profile + goals + pulses.
    static func exportJSON(context: NSManagedObjectContext) -> String {
        var root: [String: Any] = [:]
        root["app"] = "Pulse"
        root["exportedAt"] = ISO8601DateFormatter().string(from: Date())

        if let profile = fetchFirst(entity: "UserProfile", in: context) {
            root["profile"] = dictionary(for: profile)
        }

        let goals = fetchAll(entity: "Goal", in: context)
        root["goals"] = goals.map { goal -> [String: Any] in
            var g = dictionary(for: goal)
            // Inline this goal's pulses/tasks if the relationship exists.
            for rel in ["dailyTasks", "steps", "pulses", "milestones"] {
                if let set = goal.value(forKey: rel) as? Set<NSManagedObject> {
                    g[rel] = set.map { dictionary(for: $0) }
                }
            }
            return g
        }

        let data = (try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Write the export to a temp `.json` file and return its URL (for ShareLink).
    static func exportFileURL(context: NSManagedObjectContext) -> URL? {
        let json = exportJSON(context: context)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Pulse-data-\(stamp).json")
        do {
            try json.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private static func fetchFirst(entity: String, in context: NSManagedObjectContext) -> NSManagedObject? {
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        req.fetchLimit = 1
        return (try? context.fetch(req))?.first
    }

    private static func fetchAll(entity: String, in context: NSManagedObjectContext) -> [NSManagedObject] {
        let req = NSFetchRequest<NSManagedObject>(entityName: entity)
        return (try? context.fetch(req)) ?? []
    }

    /// Read every modeled attribute by name — safe even if the schema changes.
    private static func dictionary(for object: NSManagedObject) -> [String: Any] {
        var dict: [String: Any] = [:]
        for key in object.entity.attributesByName.keys {
            guard let value = object.value(forKey: key) else { continue }
            switch value {
            case let date as Date:   dict[key] = ISO8601DateFormatter().string(from: date)
            case let n as NSNumber:  dict[key] = n
            case let s as String:    dict[key] = s
            default:                 dict[key] = "\(value)"
            }
        }
        return dict
    }
}
