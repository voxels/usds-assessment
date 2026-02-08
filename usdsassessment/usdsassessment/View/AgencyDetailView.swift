import SwiftUI

struct AgencyDetailView: View {
    @State private var viewModel: AgencyDetailViewModel
    @Environment(ProcessingStore.self) private var processingStore

    init(agency: Agency, dataService: DataServiceProtocol) {
        _viewModel = State(initialValue: AgencyDetailViewModel(agency: agency, dataService: dataService))
    }
    
    private func refreshSummary() async {
        processingStore.startProcessing(viewModel.agency.slug)
        await viewModel.fetchSummary(force: true)
        processingStore.stopProcessing(viewModel.agency.slug)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                if !viewModel.tags.isEmpty { tagsSection }
                summaryContent
                amendmentsSection
            }
            .padding()
        }
        .refreshable {
            // Trigger both AI refresh and data reload
            await refreshSummary()
            await viewModel.loadAmendments()
        }
        .navigationTitle(viewModel.agency.shortName ?? viewModel.agency.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadSummary() }
        .toolbar {
            ToolbarItem {
                ShareLink(item: viewModel.reportText,
                          preview: SharePreview("\(viewModel.agency.name) Report")) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem {
                Button { Task { await refreshSummary() } } label: {
                    Label("Refresh AI", systemImage: "sparkles")
                }
                .disabled(viewModel.isRefreshing)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        GroupBox(label: Label("Quick Stats", systemImage: "chart.bar.fill")) {
            VStack(alignment: .leading, spacing: 8) {
                row("Regulatory Footprint:", "\(viewModel.agency.wordCountProxy) est. words")
                row("Last Amended:", viewModel.agency.latestAmendedOn ?? "Unknown")
                row("Data Checksum:", String((viewModel.agency.checksum ?? "N/A").prefix(12)) + "…")
            }
            .padding(.top, 4)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).bold() }
    }

    private var tagsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(viewModel.tags, id: \.self) { tag in
                    Text(tag).font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.blue.opacity(0.15)).clipShape(Capsule())
                }
            }
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let s = viewModel.agency.summary {
            VStack(alignment: .leading, spacing: 16) {
                card("Latest Title Changes", s.latestTitleChange)
                card("Recent Batch Highlights", s.recentBatch)
                card("Changes Since 2023", s.changesSince2023)
                card("2023 Baseline", s.baseline2023)
                Text("Generated: \(s.generatedAt)").font(.caption2).foregroundColor(.secondary)
            }
        } else if viewModel.isRefreshing {
            ProgressView("Fetching latest insights...")
                .frame(maxWidth: .infinity).padding(.vertical, 40)
        } else {
            VStack(spacing: 20) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 50)).foregroundColor(.secondary)
                if let error = viewModel.error {
                    Text("Error Generating Summary").font(.headline).foregroundColor(.red)
                    Text(error).font(.caption).multilineTextAlignment(.center).padding(.horizontal)
                } else {
                    Text("No AI Summary Available").font(.headline)
                }
                Button("Generate AI Insights") { Task { await refreshSummary() } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 40)
        }
    }

    private func card(_ title: String, _ content: String) -> some View {
        GroupBox(label: Text(title).font(.subheadline).bold()) {
            Text(.init(content)).font(.body).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
        }
    }

    @ViewBuilder
    private var amendmentsSection: some View {
        if !viewModel.amendments.isEmpty {
            GroupBox(label: Label("Recent Amendments", systemImage: "clock.arrow.circlepath")) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(viewModel.amendments) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.date).font(.caption).bold().foregroundColor(.secondary)
                                Spacer()
                                Text(item.title).font(.caption2).padding(4).background(Color.blue.opacity(0.1)).cornerRadius(4)
                            }
                            Text(item.heading).font(.subheadline).bold().lineLimit(2)
                            if let desc = item.description, !desc.isEmpty {
                                 Text(desc).font(.caption).foregroundStyle(.secondary)
                            }
                            if let urlString = item.url, let link = URL(string: urlString) {
                                Link("View on eCFR", destination: link).font(.caption)
                            }
                        }
                        Divider()
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
