import SwiftUI
import CoreData

// MARK: - Settings View
// CloudDesign merges settings into MyProfile. This view exists for
// backward-compatibility with any NavigationLinks still pointing here.
// It simply re-uses ProfileView's layout.

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(AppState.self) private var appState

    var body: some View {
        ProfileView()
    }
}
