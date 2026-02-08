import SwiftUI
import SwiftData

/// App-level state: owns sync lifecycle and navigation selection.
@Observable
@MainActor
final class AppViewModel {
    var selectedDepartment: Agency?
    var selectedAgency: Agency?
    var activeTool: SidebarTool?
    var isSyncing = false
    var syncError: String?

    private var syncService: SyncService?

    func configure(dataService: DataServiceProtocol) {
        // SyncService creates its own container via makeDefault
        syncService = SyncService.makeDefault()
        Task {
            await syncService?.startListening()
        }
    }

    func syncOnLaunch() async {
        guard let syncService else { return }
        isSyncing = true
        do {
            // First manual sync to ensure fresh data immediately
            let _ = try await syncService.sync()
        } catch {
            syncError = error.localizedDescription
        }
        isSyncing = false
    }
}
