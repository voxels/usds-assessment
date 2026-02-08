import SwiftUI
import SwiftData

struct AgencyListView: View {
    var department: Agency?
    @Binding var selectedAgency: Agency?

    @Query private var allAgencies: [Agency]

    var filteredAgencies: [Agency] {
        guard let department = department else { return [] }
        return allAgencies.filter {
            $0.parentAgencyName == department.name || $0.slug == department.slug
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        List(selection: $selectedAgency) {
            if let dept = department {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dept.name)
                            .font(.title2)
                            .bold()
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(filteredAgencies.count) Agencies")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            
            ForEach(filteredAgencies) { agency in
                NavigationLink(value: agency) {
                    VStack(alignment: .leading) {
                        Text(agency.name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if agency.summary != nil {
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
        .navigationBarTitleDisplayMode(.inline)
    }
}
