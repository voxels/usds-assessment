import Foundation

/// Abstraction for all data fetching. Swap `NetworkService` for `MockDataService` in tests.
protocol DataServiceProtocol: Sendable {
    func fetchAgencies() async throws -> [AgencyTransfer]
    func fetchSummary(for slug: String, force: Bool) async throws -> SummaryTransfer
    func fetchStats() async throws -> StatsTransfer
    func fetchRecentAmendments(for slug: String) async throws -> [AmendmentTransfer]
    func fetchGlobalAmendments() async throws -> [AmendmentTransfer]
}
