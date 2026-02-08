import Foundation

// MARK: - Agency Transfer (JSON ↔ Swift)

struct AgencyTransfer: Codable, Sendable {
    let slug: String
    let agencyId: String
    let name: String
    let shortName: String?
    let parentAgencyName: String?
    let wordCountProxy: Int
    let checksum: String?
    let analyzedAt: String?
    let latestAmendedOn: String?

    enum CodingKeys: String, CodingKey {
        case slug, name, checksum
        case agencyId = "id"
        case shortName = "short_name"
        case parentAgencyName = "parent_agency_name"
        case wordCountProxy = "word_count_proxy"
        case analyzedAt = "analyzed_at"
        case latestAmendedOn = "latest_amended_on"
    }

    init(slug: String, agencyId: String = "", name: String, shortName: String? = nil,
         parentAgencyName: String? = nil, wordCountProxy: Int = 0, checksum: String? = nil,
         analyzedAt: String? = nil, latestAmendedOn: String? = nil) {
        self.slug = slug; self.agencyId = agencyId; self.name = name
        self.shortName = shortName; self.parentAgencyName = parentAgencyName
        self.wordCountProxy = wordCountProxy; self.checksum = checksum
        self.analyzedAt = analyzedAt; self.latestAmendedOn = latestAmendedOn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        name = try c.decode(String.self, forKey: .name)
        shortName = try c.decodeIfPresent(String.self, forKey: .shortName)
        parentAgencyName = try c.decodeIfPresent(String.self, forKey: .parentAgencyName)
        wordCountProxy = try c.decodeIfPresent(Int.self, forKey: .wordCountProxy) ?? 0
        checksum = try c.decodeIfPresent(String.self, forKey: .checksum)
        analyzedAt = try c.decodeIfPresent(String.self, forKey: .analyzedAt)
        latestAmendedOn = try c.decodeIfPresent(String.self, forKey: .latestAmendedOn)
        // Handle id as String or Int
        if let s = try? c.decode(String.self, forKey: .agencyId) { agencyId = s }
        else if let i = try? c.decode(Int.self, forKey: .agencyId) { agencyId = String(i) }
        else { agencyId = UUID().uuidString }
    }
}

// MARK: - Summary Transfer

struct SummaryTransfer: Codable, Sendable {
    let agency: String
    let checksum: String?
    let generatedAt: String
    let summaries: SummaryFields

    struct SummaryFields: Codable, Sendable {
        let baseline2023: String
        let changesSince2023: String
        let recentBatch: String
        let latestTitleChange: String

        enum CodingKeys: String, CodingKey {
            case baseline2023 = "baseline_2023"
            case changesSince2023 = "changes_since_2023"
            case recentBatch = "recent_batch"
            case latestTitleChange = "latest_title_change"
        }
    }

    enum CodingKeys: String, CodingKey {
        case agency, checksum, summaries
        case generatedAt = "generated_at"
    }
}

struct SummaryResponse: Codable, Sendable {
    let status: String
    let data: SummaryTransfer
}

// MARK: - Stats Transfer

struct StatsTransfer: Codable, Sendable {
    let topAgencies: [TopAgency]
    let titleStats: [TitleStat]
    let timeline: [TimelinePoint]
    let updatedAt: String

    struct TopAgency: Codable, Sendable {
        let name: String
        let value: Int
    }

    struct TimelinePoint: Codable, Sendable {
        let year: String
        let organization: String
        let count: Int
    }

    struct TitleStat: Codable, Sendable {
        let title: String
        let count: Int
        let agencies: [String]
    }

    enum CodingKeys: String, CodingKey {
        case topAgencies = "top_agencies"
        case titleStats = "title_stats"
        case timeline
        case updatedAt = "updated_at"
    }
}

struct StatsResponse: Codable, Sendable {
    let status: String
    let data: StatsTransfer
}

// MARK: - Amendment Transfer

struct AmendmentTransfer: Codable, Sendable, Identifiable {
    var id: String { date + heading }
    let date: String
    let heading: String
    let title: String
    let description: String?
    let url: String?
}

struct AmendmentsResponse: Codable, Sendable {
    let status: String
    let data: [AmendmentTransfer]
}
