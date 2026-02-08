import SwiftUI
import SwiftData
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct usdsassessmentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Agency.self, AgencySummary.self, ChecksumRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema migration failed — delete old store and retry
            print("⚠️ ModelContainer failed: \(error). Resetting store...")
            let url = config.url
            for ext in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ext))
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // Last resort: run with an in-memory store so the app doesn't crash
                print("‼️ ModelContainer reset also failed: \(error). Falling back to in-memory store.")
                let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try! ModelContainer(for: schema, configurations: [memoryConfig])
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
