import SwiftUI
import Charts
import SwiftData

struct GlobalDashboardView: View {
    @Binding var activeTool: SidebarTool?
    @Binding var selectedAgency: Agency?
    @Query private var allAgencies: [Agency]
    @Query(sort: \ChecksumRecord.recordedAt, order: .reverse) private var recentChanges: [ChecksumRecord]
    @State private var viewModel = DashboardViewModel(dataService: NetworkService.shared)

    private var withSummary: Int { allAgencies.filter { $0.summary != nil }.count }
    private var withoutSummary: Int { allAgencies.count - withSummary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Federal Regulatory Overview")
                    .font(.largeTitle).bold()

                if viewModel.isLoading {
                    ProgressView("Loading global stats...")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else if let stats = viewModel.stats {
                    // Top Agencies (Server Data)
                    GroupBox(label: Label("Regulatory Volume (Estimated Word Count)", systemImage: "doc.text.fill")) {
                        footprintChart(stats: stats)
                            .frame(height: CGFloat(max(300, stats.topAgencies.count * 50)))
                            .padding(.top)
                    }

                    // Recent Changes Summary
                    if !recentChanges.isEmpty {
                        GroupBox(label: Label("What's Changed", systemImage: "clock.arrow.circlepath")) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(recentChanges.prefix(3))) { change in
                                    Button {
                                        if let agency = allAgencies.first(where: { $0.slug == change.agencySlug }) {
                                            selectedAgency = agency
                                        }
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(change.agencyName).font(.subheadline).bold()
                                                Text("Update detected on \(change.recordedAt.formatted(date: .abbreviated, time: .omitted))")
                                                    .font(.caption).foregroundColor(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                        }
                                        .contentShape(Rectangle()) // Make full row tappable
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 4)
                                    Divider()
                                }
                                Button("See All Changes") {
                                    activeTool = .changes
                                }
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 4)
                            }
                            .padding(.top)
                        }
                    }

                    // CFR Title Distribution (Server Data)
                    GroupBox(label: Label("CFR Title Distribution", systemImage: "books.vertical")) {
                        titleStatsChart(stats: stats)
                            .frame(height: CGFloat(max(300, stats.titleStats.count * 80)))
                            .padding(.top)
                    }

                    Text("Stats updated: \(stats.updatedAt)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let error = viewModel.error {
                    ContentUnavailableView("Unable to Load Stats", systemImage: "exclamationmark.triangle", description: Text(error))
                }
            }
            .padding()
            
            // System Status (Local Data)
            GroupBox(label: Label("System Status", systemImage: "server.rack")) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statusCard("Total Agencies", value: "\(allAgencies.count)", icon: "building.2")
                    statusCard("Analyzed", value: "\(withSummary)", icon: "sparkles")
                    statusCard("Pending", value: "\(withoutSummary)", icon: "clock")
                    statusCard("Favorited", value: "\(allAgencies.filter { $0.isFavorite }.count)", icon: "star.fill")
                }
                .padding(.top, 4)
            }
            
            // Completeness (Local Data)
            GroupBox(label: Label("Analysis Completeness", systemImage: "brain.head.profile")) {
                completenessChart
                    .frame(height: 180)
                    .padding(.top)
            }
        
        }
        .task {
            await viewModel.loadStats()
        }
    }

    // MARK: - Charts

    private var completenessChart: some View {
        let data: [(String, Int)] = [
            ("Analyzed", withSummary),
            ("Pending", withoutSummary)
        ]
        return Chart(data, id: \.0) { item in
            SectorMark(angle: .value("Count", item.1),
                       innerRadius: .ratio(0.6))
                .foregroundStyle(by: .value("Status", item.0))
        }
        .chartForegroundStyleScale(["Analyzed": .green, "Pending": .orange])
        .chartBackground { proxy in
            GeometryReader { geo in
                let frame = geo[proxy.plotFrame!]
                VStack {
                    Text("\(withSummary)")
                        .font(.title2.bold())
                    Text("Analyzed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .position(x: frame.midX, y: frame.midY)
            }
        }
    }

    private func footprintChart(stats: StatsTransfer) -> some View {
        Chart(stats.topAgencies, id: \.name) { agency in
            BarMark(
                x: .value("Words", agency.value),
                y: .value("Agency", agency.name)
            )
            .annotation(position: .trailing) {
                Text("\(agency.value)")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
    }



    private func titleStatsChart(stats: StatsTransfer) -> some View {
        Chart(stats.titleStats, id: \.title) { item in
            BarMark(
                x: .value("Agencies Amended", item.count),
                y: .value("Title", item.title)
            )
            .annotation(position: .trailing, alignment: .leading) {
                Text("\(item.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                if let title = value.as(String.self),
                   let stat = stats.titleStats.first(where: { $0.title == title }) {
                    AxisValueLabel {
                        VStack(alignment: .leading) {
                            Text(title)
                                .font(.caption)
                                .bold()
                            Text(stat.agencies.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: 180, alignment: .leading)
                    }
                }
            }
        }
        .chartXAxisLabel("Agencies Amended Since 2024")
    }

    private func statusCard(_ title: String, value: String, icon: String) -> some View {
        VStack {
            Image(systemName: icon)
                .font(.title2).foregroundColor(.accentColor)
            Text(value).font(.title).bold()
            Text(title).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}
