import XCTest
import SwiftData
@testable import usdsassessment

// MARK: - Mock Data Service

final class MockDataService: DataServiceProtocol, @unchecked Sendable {
    var agenciesToReturn: [AgencyTransfer] = []
    var summaryToReturn: SummaryTransfer?
    var statsToReturn: StatsTransfer?
    var shouldThrow = false

    func fetchAgencies() async throws -> [AgencyTransfer] {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return agenciesToReturn
    }

    func fetchSummary(for slug: String, force: Bool) async throws -> SummaryTransfer {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        guard let summary = summaryToReturn else { throw URLError(.badServerResponse) }
        return summary
    }

    func fetchStats() async throws -> StatsTransfer {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        guard let stats = statsToReturn else { throw URLError(.badServerResponse) }
        return stats
    }

    func fetchRecentAmendments(for slug: String) async throws -> [AmendmentTransfer] {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return []
    }

    func fetchGlobalAmendments() async throws -> [AmendmentTransfer] {
        if shouldThrow { throw URLError(.notConnectedToInternet) }
        return []
    }
}

// MARK: - Transfer Model Decoding Tests

final class TransferModelTests: XCTestCase {
    func testAgencyDecoding_stringId() throws {
        let json = """
        {"slug":"test-dept","id":"123","name":"Test Department","word_count_proxy":500}
        """.data(using: .utf8)!
        let agency = try JSONDecoder().decode(AgencyTransfer.self, from: json)
        XCTAssertEqual(agency.slug, "test-dept")
        XCTAssertEqual(agency.agencyId, "123")
        XCTAssertEqual(agency.wordCountProxy, 500)
    }

    func testAgencyDecoding_intId() throws {
        let json = """
        {"slug":"int-dept","id":42,"name":"Int Agency"}
        """.data(using: .utf8)!
        let agency = try JSONDecoder().decode(AgencyTransfer.self, from: json)
        XCTAssertEqual(agency.agencyId, "42")
    }

    func testAgencyDecoding_missingId() throws {
        let json = """
        {"slug":"no-id","name":"No ID Agency"}
        """.data(using: .utf8)!
        let agency = try JSONDecoder().decode(AgencyTransfer.self, from: json)
        XCTAssertFalse(agency.agencyId.isEmpty) // Should get UUID fallback
    }

    func testAgencyDecoding_missingOptionals() throws {
        let json = """
        {"slug":"minimal","name":"Minimal"}
        """.data(using: .utf8)!
        let agency = try JSONDecoder().decode(AgencyTransfer.self, from: json)
        XCTAssertEqual(agency.wordCountProxy, 0)
        XCTAssertNil(agency.checksum)
        XCTAssertNil(agency.shortName)
        XCTAssertNil(agency.latestAmendedOn)
    }

    func testSummaryResponseDecoding() throws {
        let json = """
        {
            "status": "success",
            "data": {
                "agency": "Test Agency",
                "checksum": "abc123",
                "generated_at": "2026-01-01T00:00:00Z",
                "summaries": {
                    "baseline_2023": "Baseline text",
                    "changes_since_2023": "Changes text",
                    "recent_batch": "Recent text",
                    "latest_title_change": "Title text"
                }
            }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(SummaryResponse.self, from: json)
        XCTAssertEqual(response.data.agency, "Test Agency")
        XCTAssertEqual(response.data.summaries.baseline2023, "Baseline text")
    }

    func testStatsDecoding() throws {
        let json = """
        {
            "status": "success",
            "data": {
                "top_agencies": [{"name": "Agency A", "value": 100}],
                "title_distribution": {"Title 1": 10, "Title 2": 5},
                "timeline": {"2024": 50, "2023": 40},
                "updated_at": "2026-02-08T00:00:00Z"
            }
        }
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(StatsResponse.self, from: json)
        XCTAssertEqual(response.data.topAgencies.first?.name, "Agency A")
        XCTAssertEqual(response.data.titleDistribution["Title 1"], 10)
        XCTAssertEqual(response.data.timeline["2024"], 50)
    }
}

// MARK: - TagExtractor Tests

final class TagExtractorTests: XCTestCase {
    func testExtractsTopKeywords() {
        let text = "Healthcare policy healthcare reform environmental regulation healthcare standards"
        let tags = TagExtractor.extractTags(from: text, count: 3)
        XCTAssertEqual(tags.first, "Healthcare")
        XCTAssertTrue(tags.count <= 3)
    }

    func testFiltersStopWords() {
        let text = "the and for but with this that from"
        let tags = TagExtractor.extractTags(from: text)
        XCTAssertTrue(tags.isEmpty)
    }

    func testFiltersShortWords() {
        let text = "do it an be go so"
        let tags = TagExtractor.extractTags(from: text)
        XCTAssertTrue(tags.isEmpty)
    }

    func testEmptyInput() {
        let tags = TagExtractor.extractTags(from: "")
        XCTAssertTrue(tags.isEmpty)
    }

    func testCapitalizesOutput() {
        let text = "environment environment environment environment environment"
        let tags = TagExtractor.extractTags(from: text)
        XCTAssertEqual(tags.first, "Environment")
    }
}

// MARK: - SyncService Tests

final class SyncServiceTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Agency.self, AgencySummary.self, ChecksumRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testSyncInsertsNewAgencies() async throws {
        let container = try makeContainer()
        let mock = MockDataService()
        mock.agenciesToReturn = [
            AgencyTransfer(slug: "test-dept", agencyId: "1", name: "Test Dept"),
            AgencyTransfer(slug: "other-dept", agencyId: "2", name: "Other Dept")
        ]

        let service = SyncService(container: container, dataService: mock)
        let result = try await service.sync()

        XCTAssertEqual(result.inserted, 2)
        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.total, 2)
    }

    func testSyncUpdatesOnChecksumChange() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Pre-populate
        let existing = Agency(from: AgencyTransfer(slug: "test", agencyId: "1", name: "Old Name", checksum: "old"))
        context.insert(existing)
        try context.save()

        let mock = MockDataService()
        mock.agenciesToReturn = [
            AgencyTransfer(slug: "test", agencyId: "1", name: "New Name", checksum: "new")
        ]

        let service = SyncService(container: container, dataService: mock)
        let result = try await service.sync()

        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.inserted, 0)
    }

    func testSyncSkipsWhenChecksumMatches() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let existing = Agency(from: AgencyTransfer(slug: "test", agencyId: "1", name: "Same", checksum: "same"))
        context.insert(existing)
        try context.save()

        let mock = MockDataService()
        mock.agenciesToReturn = [
            AgencyTransfer(slug: "test", agencyId: "1", name: "Same", checksum: "same")
        ]

        let service = SyncService(container: container, dataService: mock)
        let result = try await service.sync()

        XCTAssertEqual(result.updated, 0)
        XCTAssertEqual(result.inserted, 0)
    }

    func testSyncAutoFavoritesPriorityAgencies() async throws {
        let container = try makeContainer()
        let mock = MockDataService()
        mock.agenciesToReturn = [
            AgencyTransfer(slug: "defense-department", agencyId: "1", name: "DoD"),
            AgencyTransfer(slug: "random-agency", agencyId: "2", name: "Random")
        ]

        let service = SyncService(container: container, dataService: mock)
        let _ = try await service.sync()

        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<Agency>())
        let dod = all.first { $0.slug == "defense-department" }
        let random = all.first { $0.slug == "random-agency" }

        XCTAssertTrue(dod?.isFavorite ?? false)
        XCTAssertFalse(random?.isFavorite ?? true)
    }

    func testSyncHandlesNetworkError() async throws {
        let container = try makeContainer()
        let mock = MockDataService()
        mock.shouldThrow = true

        let service = SyncService(container: container, dataService: mock)

        do {
            let _ = try await service.sync()
            XCTFail("Expected error")
        } catch {
            // Expected
        }
    }
}
