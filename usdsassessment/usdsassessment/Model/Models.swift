import Foundation
import SwiftData

// MARK: - Agency

@Model
final class Agency {
    @Attribute(.unique) var slug: String
    var agencyId: String
    var name: String
    var shortName: String?
    var parentAgencyName: String?
    var wordCountProxy: Int
    var checksum: String?
    var analyzedAt: String?
    var latestAmendedOn: String?
    var isFavorite: Bool = false
    @Relationship(deleteRule: .cascade) var summary: AgencySummary?

    init(from transfer: AgencyTransfer) {
        self.slug = transfer.slug
        self.agencyId = transfer.agencyId
        self.name = transfer.name
        self.shortName = transfer.shortName
        self.parentAgencyName = transfer.parentAgencyName
        self.wordCountProxy = transfer.wordCountProxy
        self.checksum = transfer.checksum
        self.analyzedAt = transfer.analyzedAt
        self.latestAmendedOn = transfer.latestAmendedOn
    }

    func update(from transfer: AgencyTransfer) {
        name = transfer.name
        shortName = transfer.shortName
        parentAgencyName = transfer.parentAgencyName
        wordCountProxy = transfer.wordCountProxy
        checksum = transfer.checksum
        analyzedAt = transfer.analyzedAt
        latestAmendedOn = transfer.latestAmendedOn
    }
}

// MARK: - Summary

@Model
final class AgencySummary {
    @Attribute(.unique) var agency: String
    var baseline2023: String
    var changesSince2023: String
    var recentBatch: String
    var latestTitleChange: String
    var generatedAt: String
    var checksum: String?

    var fullText: String {
        [baseline2023, changesSince2023, recentBatch, latestTitleChange].joined(separator: " ")
    }

    init(from transfer: SummaryTransfer) {
        self.agency = transfer.agency
        self.checksum = transfer.checksum
        self.generatedAt = transfer.generatedAt
        self.baseline2023 = transfer.summaries.baseline2023
        self.changesSince2023 = transfer.summaries.changesSince2023
        self.recentBatch = transfer.summaries.recentBatch
        self.latestTitleChange = transfer.summaries.latestTitleChange
    }

    func update(from transfer: SummaryTransfer) {
        checksum = transfer.checksum
        generatedAt = transfer.generatedAt
        baseline2023 = transfer.summaries.baseline2023
        changesSince2023 = transfer.summaries.changesSince2023
        recentBatch = transfer.summaries.recentBatch
        latestTitleChange = transfer.summaries.latestTitleChange
    }
}

// MARK: - Checksum Record

@Model
final class ChecksumRecord {
    var agencySlug: String
    var agencyName: String
    var previousChecksum: String?
    var newChecksum: String
    var recordedAt: Date

    init(agencySlug: String, agencyName: String, previousChecksum: String?, newChecksum: String) {
        self.agencySlug = agencySlug
        self.agencyName = agencyName
        self.previousChecksum = previousChecksum
        self.newChecksum = newChecksum
        self.recordedAt = Date()
    }
}
