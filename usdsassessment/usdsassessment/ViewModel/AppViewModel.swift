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

    var globalAmendments: [AmendmentTransfer] = []
    
    private var syncService: SyncService?
    private var dataService: DataServiceProtocol?

    func configure(dataService: DataServiceProtocol) {
        self.dataService = dataService
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
            // Parallel fetch: Sync + Global Amendments
            async let sync:Int = syncService.sync()
            async let amendments = dataService?.fetchGlobalAmendments() ?? []
            
            let (_, fetchedAmendments) = try await (sync, amendments)
            self.globalAmendments = fetchedAmendments
        } catch {
            print("Sync/Fetch Error: \(error)")
            syncError = error.localizedDescription
        }
        isSyncing = false
    }
}
