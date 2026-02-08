import SwiftUI

/// Manages summary loading, export, and tags for a single agency.
@Observable
@MainActor
final class AgencyDetailViewModel {
    let agency: Agency
    var isRefreshing = false
    var error: String?

    private let dataService: DataServiceProtocol

    var tags: [String] = []
    var amendments: [AmendmentTransfer] = []

    var reportText: String {
        var r = "# \(agency.name)\n\n"
        r += "- Footprint: \(agency.wordCountProxy) est. words\n"
        r += "- Last Amended: \(agency.latestAmendedOn ?? "Unknown")\n\n"
        if let s = agency.summary {
            r += "## 2023 Baseline\n\(s.baseline2023)\n\n"
            r += "## Changes Since 2023\n\(s.changesSince2023)\n\n"
            r += "## Recent Highlights\n\(s.recentBatch)\n\n"
            r += "## Title Changes\n\(s.latestTitleChange)\n\n"
            r += "---\nGenerated: \(s.generatedAt)\n"
        }
        return r
    }

    init(agency: Agency, dataService: DataServiceProtocol) {
        self.agency = agency
        self.dataService = dataService
    }

    func loadSummary() async {
        await loadAmendments()
        if agency.summary != nil {
            await generateTags()
        } else {
            await fetchSummary(force: false)
        }
    }
    
    func loadAmendments() async {
        do {
            let fetched = try await dataService.fetchRecentAmendments(for: agency.slug)
            await MainActor.run {
                self.amendments = fetched.sorted { $0.date > $1.date }
            }
        } catch {
             print("Failed to fetch amendments: \(error)")
        }
    }

    func fetchSummary(force: Bool) async {
        isRefreshing = true
        do {
            let transfer = try await dataService.fetchSummary(for: agency.slug, force: force)
            await MainActor.run {
                if let existing = agency.summary {
                    existing.update(from: transfer)
                } else {
                    agency.summary = AgencySummary(from: transfer)
                }
                isRefreshing = false
            }
            await generateTags()
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                isRefreshing = false
            }
        }
    }

    private func generateTags() async {
        guard let text = agency.summary?.fullText else { return }
        let extracted = await Task.detached(priority: .userInitiated) {
            return TagExtractor.extractTags(from: text)
        }.value
        await MainActor.run {
            self.tags = extracted
        }
    }
}
