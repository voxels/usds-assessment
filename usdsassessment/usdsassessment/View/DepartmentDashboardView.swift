import SwiftUI
import Charts
import SwiftData

struct DepartmentDashboardView: View {
    let department: Agency
    let agencies: [Agency]
    @Binding var selectedAgency: Agency?
    var dataService: DataServiceProtocol = NetworkService.shared
    
    @State private var amendments: [AmendmentTransfer] = []
    @State private var selectedAmendment: AmendmentTransfer?
    @State private var isRefreshingSummary = false
    @Query(sort: \ChecksumRecord.recordedAt, order: .reverse) private var allChanges: [ChecksumRecord]
    
    // MARK: - Computed Stats
    
    private var analyzedCount: Int { agencies.filter { $0.summary != nil }.count }
    private var pendingCount: Int { agencies.count - analyzedCount }
    
    private var totalWordCount: Int {
        agencies.reduce(0) { $0 + $1.wordCountProxy }
    }
    
    private var recentDepartmentChanges: [ChecksumRecord] {
        let agencySlugs = Set(agencies.map { $0.slug })
        return allChanges.filter { agencySlugs.contains($0.agencySlug) }
    }
    
    private var topAgenciesByVolume: [Agency] {
        agencies.sorted { $0.wordCountProxy > $1.wordCountProxy }.prefix(5).map { $0 }
    }
    
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Header Stats
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            VStack(spacing: 12) {
                                statCard("Agencies", value: "\(agencies.count)", icon: "building.2")
                                statCard("Total Words", value: formatNumber(totalWordCount), icon: "doc.text")
                            }
                            statCard("Analyzed", value: "\(analyzedCount)", icon: "sparkles")
                        }
                    }
                    .frame(maxWidth:proxy.size.width)
                    .padding(.vertical) // Add padding back since row insets are 0
                    
                    // Completeness & Volume Charts
                    if !agencies.isEmpty {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 16) {
                                GroupBox(label: Label("Completeness", systemImage: "chart.pie.fill")) {
                                    completenessChart.frame(width: 200, height: 150)
                                }
                                
                                GroupBox(label: Label("Top Agencies (Volume)", systemImage: "chart.bar.fill")) {
                                    volumeChart.frame(width: 300, height: 150)
                                }
                            }
                            .padding(.vertical) // Content padding inside scroll
                        }
                    }
                    
                    // Department-Level AI Summary
                    summarySection
                    
                    // Regulatory Amendments (API)
                    if !amendments.isEmpty {
                        GroupBox(label: Label("Recent Regulatory Amendments", systemImage: "text.book.closed.fill")) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(amendments) { amendment in
                                    Button {
                                        selectedAmendment = amendment
                                    } label: {
                                        amendmentRowContent(amendment, agencyName: agencies.first(where: { $0.slug == amendment.agencySlug })?.name)
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical)
                    }
                    
                    // Recent Activity (Local Sync)
                    if !recentDepartmentChanges.isEmpty {
                        GroupBox(label: Label("Recent Activity", systemImage: "clock.arrow.circlepath")) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(recentDepartmentChanges.prefix(3)) { change in
                                    Button {
                                        if let agency = agencies.first(where: { $0.slug == change.agencySlug }) {
                                            selectedAgency = agency
                                        }
                                    } label: {
                                        HStack {
                                            Text(change.agencyName).font(.caption).bold()
                                            Spacer()
                                            Text(change.recordedAt.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    Divider()
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical)
                    }
                }
                .padding(.vertical, 8)
            }
            .sheet(item: $selectedAmendment) { amendment in
                AmendmentDetailView(amendment: amendment, agencies: agencies, selectedAgency: $selectedAgency)
            }
            .task {
                do {
                    amendments = try await NetworkService.shared.fetchRecentAmendments(for: department.slug)
                } catch {
                    print("Failed to fetch department amendments: \(error)")
                }
            }
        }
    }
        
        // MARK: - Subviews
        
        private func statCard(_ title: String, value: String, icon: String) -> some View {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: icon).foregroundStyle(.blue)
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Text(value).font(.headline).bold()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)
        }
        
        private var completenessChart: some View {
            Chart {
                SectorMark(angle: .value("Analyzed", analyzedCount), innerRadius: .ratio(0.6))
                    .foregroundStyle(.green)
                SectorMark(angle: .value("Pending", pendingCount), innerRadius: .ratio(0.6))
                    .foregroundStyle(.orange)
            }
            .chartBackground { proxy in
                Text("\(Int((Double(analyzedCount) / Double(max(1, agencies.count))) * 100))%")
                    .font(.title3.bold())
            }
        }
        
        private var volumeChart: some View {
            Chart(topAgenciesByVolume) { agency in
                BarMark(
                    x: .value("Words", agency.wordCountProxy),
                    y: .value("Agency", agency.shortName ?? String(agency.name.prefix(15)))
                )
                .foregroundStyle(.blue.gradient)
            }
            .chartXAxis(.hidden)
        }
        
    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .scientific
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func amendmentRowContent(_ amendment: AmendmentTransfer, agencyName: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(amendment.date).font(.caption).bold().foregroundColor(.secondary)
                Spacer()
                if let name = agencyName {
                    Text(name)
                        .font(.caption2)
                        .padding(4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            Text(amendment.heading).font(.subheadline).bold().multilineTextAlignment(.leading)
            if let description = amendment.description {
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .contentShape(Rectangle())
    }
        
        // MARK: - Summary Section
        
        @ViewBuilder
        private var summarySection: some View {
            if let s = department.summary {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Department Analysis", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.headline)
                    
                    // Show Recent Batch (most relevant for departments)
                    card("Recent Regulatory Updates", s.recentBatch)
                    
                    // Show Changes Since 2023
                    card("Key Changes Since 2023", s.changesSince2023)
                    
                    HStack {
                        Text("Generated: \(s.generatedAt)").font(.caption2).foregroundColor(.secondary)
                        Spacer()
                        Button {
                            Task { await refreshSummary() }
                        } label: {
                            if isRefreshingSummary {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Refresh Analysis", systemImage: "arrow.clockwise").font(.caption)
                            }
                        }
                        .disabled(isRefreshingSummary)
                    }
                }
                .padding(.vertical)
            } else {
                GroupBox {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Department Analysis").font(.headline)
                            Text("Generate an AI summary of recent regulatory changes across this department.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await refreshSummary() }
                        } label: {
                            if isRefreshingSummary {
                                ProgressView()
                            } else {
                                Text("Generate")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRefreshingSummary)
                    }
                }
                .padding(.vertical)
            }
        }
        
        private func card(_ title: String, _ content: String) -> some View {
            GroupBox(label: Text(title).font(.subheadline).bold()) {
                Text(.init(content)).font(.body).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
        
        private func refreshSummary() async {
            isRefreshingSummary = true
            do {
                let summary = try await dataService.fetchSummary(for: department.slug, force: true)
                // Update local model (SwiftData will update via binding/query if mapped, but here we might need to manually update if `department` is a let constant.
                // Actually `department` is a SwiftData object, so we can update its properties on the main actor)
                
                if let existing = department.summary {
                    existing.update(from: summary)
                } else {
                    department.summary = AgencySummary(from: summary)
                }
            } catch {
                print("Summary generation failed: \(error)")
            }
            isRefreshingSummary = false
        }
    }
    
// MARK: - Detail Sheet

struct AmendmentDetailView: View {
    let amendment: AmendmentTransfer
    let agencies: [Agency]
    @Binding var selectedAgency: Agency?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(amendment.date)
                            .font(.subheadline).bold()
                            .foregroundColor(.secondary)
                        
                        Text(amendment.heading)
                            .font(.title2).bold()
                        
                        Text(amendment.title)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Description
                    if let description = amendment.description {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description").font(.headline)
                            Text(description)
                                .font(.body)
                        }
                    }
                    
                    Divider()
                    
                    // Actions
                    VStack(spacing: 12) {
                        // Internal Link
                        if let slug = amendment.agencySlug, let agency = agencies.first(where: { $0.slug == slug }) {
                            Button {
                                selectedAgency = agency
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "building.2.crop.circle")
                                    Text("View Agency: \(agency.shortName ?? agency.name)")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                        
                        // External Link
                        if let urlString = amendment.url, let link = URL(string: urlString) {
                            Link(destination: link) {
                                HStack {
                                    Image(systemName: "safari")
                                    Text("Read Full Text on eCFR")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Amendment Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
