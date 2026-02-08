import XCTest
@testable import usdsassessment

final class AmendmentTests: XCTestCase {
    
    // Test successful decoding of mandatory and optional fields
    func testAmendmentDecoding() throws {
        let json = """
        {
            "status": "success",
            "data": [
                {
                    "date": "2024-01-01",
                    "heading": "Section 1",
                    "title": "Title 14",
                    "description": "Test amendment",
                    "url": "https://example.com"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AmendmentsResponse.self, from: json)
        
        XCTAssertEqual(response.status, "success")
        XCTAssertEqual(response.data.count, 1)
        
        let item = response.data[0]
        XCTAssertEqual(item.date, "2024-01-01")
        XCTAssertEqual(item.heading, "Section 1")
        XCTAssertEqual(item.title, "Title 14")
        XCTAssertEqual(item.description, "Test amendment")
        XCTAssertEqual(item.url, "https://example.com")
        XCTAssertEqual(item.id, "2024-01-01Section 1") // Computed ID Logic verification
    }

    // Test robustness: missing optional fields shouldn't crash
    func testAmendmentMissingOptionalFields() throws {
        let json = """
        {
            "status": "success",
            "data": [
                {
                    "date": "2024-02-01",
                    "heading": "Part 2",
                    "title": "Title 14"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AmendmentsResponse.self, from: json)
        
        XCTAssertEqual(response.data.count, 1)
        let item = response.data[0]
        
        XCTAssertEqual(item.date, "2024-02-01")
        XCTAssertNil(item.description)
        XCTAssertNil(item.url)
    }
}
