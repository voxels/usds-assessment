import Foundation

/// Concrete implementation of DataServiceProtocol using URLSession.
final class NetworkService: DataServiceProtocol, @unchecked Sendable {
    static let shared = NetworkService()
    private let baseURL: String

    private let session: URLSession

    init(baseURL: String = "https://api-ylhco6bvia-uc.a.run.app") {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300 // 5 minutes (for AI generation)
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    private func makeRequest(to url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.addValue("assessment-admin-key", forHTTPHeaderField: "x-api-key")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    private func verifyResponse(_ response: URLResponse, _ data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error message from body
            if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                 throw NSError(domain: "NetworkService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.message])
            }
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Server returned \(httpResponse.statusCode)"])
        }
    }

    func fetchAgencies() async throws -> [AgencyTransfer] {
        let (data, response) = try await session.data(for: makeRequest(to: URL(string: "\(baseURL)/agencies")!))
        try verifyResponse(response, data)
        return try JSONDecoder().decode([AgencyTransfer].self, from: data)
    }

    func fetchSummary(for slug: String, force: Bool) async throws -> SummaryTransfer {
        var urlString = "\(baseURL)/summarize?agency_id=\(slug)"
        if force { urlString += "&force=true" }
        let (data, response) = try await session.data(for: makeRequest(to: URL(string: urlString)!))
        try verifyResponse(response, data)
        return try JSONDecoder().decode(SummaryResponse.self, from: data).data
    }

    func fetchStats() async throws -> StatsTransfer {
        let (data, response) = try await session.data(for: makeRequest(to: URL(string: "\(baseURL)/stats")!))
        try verifyResponse(response, data)
        return try JSONDecoder().decode(StatsResponse.self, from: data).data
    }

    func fetchRecentAmendments(for slug: String) async throws -> [AmendmentTransfer] {
        let (data, response) = try await session.data(for: makeRequest(to: URL(string: "\(baseURL)/amendments?agency_slug=\(slug)")!))
        try verifyResponse(response, data)
        return try JSONDecoder().decode(AmendmentsResponse.self, from: data).data
    }

    func fetchGlobalAmendments() async throws -> [AmendmentTransfer] {
        let (data, response) = try await session.data(for: makeRequest(to: URL(string: "\(baseURL)/amendments")!))
        try verifyResponse(response, data)
        return try JSONDecoder().decode(AmendmentsResponse.self, from: data).data
    }
}

struct ErrorResponse: Codable {
    let status: String
    let message: String
}
