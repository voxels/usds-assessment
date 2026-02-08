import SwiftUI
import SwiftData

@Observable
@MainActor
final class DashboardViewModel {
    var stats: StatsTransfer?
    var isLoading = false
    var error: String?
    
    private var observer: NSObjectProtocol?

    private let dataService: DataServiceProtocol

    init(dataService: DataServiceProtocol) {
        self.dataService = dataService
        
        observer = NotificationCenter.default.addObserver(forName: .didReceiveRemoteStats, object: nil, queue: .main) { [weak self] note in
            guard let self else { return }
            if let stats = note.userInfo?["stats"] as? StatsTransfer {
                Task { @MainActor in
                    self.stats = stats
                }
            }
        }
    }
    
    @MainActor deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func loadStats() async {
        isLoading = true
        error = nil
        do {
            let fetchedStats = try await dataService.fetchStats()
            await MainActor.run {
                self.stats = fetchedStats
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

