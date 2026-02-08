import SwiftUI
import SwiftData

struct AgencyListView: View {
    var department: Agency?
    @Binding var selectedAgency: Agency?
    @Environment(ProcessingStore.self) private var processingStore

    @Query private var allAgencies: [Agency]

    var filteredAgencies: [Agency] {
        guard let department = department else { return [] }
        return allAgencies.filter {
            $0.parentAgencyName == department.name || $0.slug == department.slug
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        List(selection: $selectedAgency) {
            ForEach(filteredAgencies) { agency in
                NavigationLink(value: agency) {
                    VStack(alignment: .leading) {
                        Text(agency.name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if processingStore.isProcessing(agency.slug) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Processing...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else if agency.summary != nil {
                                Label("Analyzed", systemImage: "sparkles")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            } else {
                                Label("Pending", systemImage: "clock")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                            if let date = agency.latestAmendedOn {
                                Text(date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(selectedAgency?.name ?? department?.name ?? "Agencies")
        .navigationBarTitleDisplayMode(.inline)
    }
}
