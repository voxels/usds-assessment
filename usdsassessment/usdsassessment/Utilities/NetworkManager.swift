import Foundation

/// Concrete implementation of DataServiceProtocol using URLSession.
final class NetworkService: DataServiceProtocol, @unchecked Sendable {
    static let shared = NetworkService()
    private let baseURL: String

    private let session: URLSession

    init(baseURL: String = "https://us-central1-usds-assessment-4c894.cloudfunctions.net/api") {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes (for AI generation)
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    private func makeRequest(to url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue("assessment-admin-key", forHTTPHeaderField: "x-api-key")
        return request
    }

    func fetchAgencies() async throws -> [AgencyTransfer] {
        let (data, _) = try await session.data(for: makeRequest(to: URL(string: "\(baseURL)/agencies")!))
        return try JSONDecoder().decode([AgencyTransfer].self, from: data)
    }

    func fetchSummary(for slug: String, force: Bool) async throws -> SummaryTransfer {
        var urlString = "\(baseURL)/summarize?agency_id=\(slug)"
        if force { urlString += "&force=true" }
        let (data, _) = try await session.data(for: makeRequest(to: URL(string: urlString)!))
        return try JSONDecoder().decode(SummaryResponse.self, from: data).data
    }

    func fetchStats() async throws -> StatsTransfer {
        let (data, _) = try await session.data(for: makeRequest(to: URL(string: "\(baseURL)/stats")!))
        return try JSONDecoder().decode(StatsResponse.self, from: data).data
    }

    func fetchRecentAmendments(for slug: String) async throws -> [AmendmentTransfer] {
        let (data, _) = try await session.data(for: makeRequest(to: URL(string: "\(baseURL)/amendments?agency_slug=\(slug)")!))
        return try JSONDecoder().decode(AmendmentsResponse.self, from: data).data
    }
}
