import SwiftUI
import SwiftData

struct ChangesView: View {
    @Query(sort: [SortDescriptor(\ChecksumRecord.recordedAt, order: .reverse)])
    private var allRecords: [ChecksumRecord]
    @Binding var selectedAgency: Agency?
    @Query private var agencies: [Agency]
    
    // Global Amendments from Server (Fallback)
    var globalAmendments: [AmendmentTransfer]
    
    var onRefresh: (() async -> Void)?

    var todayRecords: [ChecksumRecord] {
        let calendar = Calendar.current
        return allRecords.filter { calendar.isDateInYesterday($0.recordedAt) || calendar.isDateInToday($0.recordedAt) }
    }

    var groupedByDate: [(String, [ChecksumRecord])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let grouped = Dictionary(grouping: allRecords) { formatter.string(from: $0.recordedAt) }
        return grouped.sorted { $0.value.first!.recordedAt > $1.value.first!.recordedAt }
    }

    var body: some View {
        List(selection: $selectedAgency) {
            // Priority: Local Changes (Today)
            if !todayRecords.isEmpty {
                Section("Changed Since Last Launch") {
                    ForEach(todayRecords, id: \.agencySlug) { record in
                        if let agency = agencies.first(where: { $0.slug == record.agencySlug }) {
                            Button {
                                selectedAgency = agency
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(.orange)
                                    VStack(alignment: .leading) {
                                        Text(record.agencyName)
                                            .font(.headline)
                                        Text("Regulation data updated")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            }

            // Timeline: Local History
            if !allRecords.isEmpty {
                ForEach(groupedByDate, id: \.0) { date, records in
                    Section(date) {
                        ForEach(records, id: \.agencySlug) { record in
                            if let agency = agencies.first(where: { $0.slug == record.agencySlug }) {
                                Button {
                                    selectedAgency = agency
                                } label: {
                                    Label(record.agencyName, systemImage: "doc.badge.clock")
                                }
                                .tint(.primary) // Ensure text color is standard
                            }
                        }
                    }
                }
            } 
            
            // Global Amendments (Server)
            if !globalAmendments.isEmpty {
                Section("Latest Government Amendments") {
                    ForEach(globalAmendments) { amendment in
                        // Linked Agency Navigation
                        if let slug = amendment.agencySlug, let agency = agencies.first(where: { $0.slug == slug }) {
                            Button {
                                selectedAgency = agency
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(amendment.date).font(.caption).bold().foregroundColor(.secondary)
                                        Spacer()
                                        Text(agency.shortName ?? agency.name)
                                            .font(.caption2)
                                            .padding(4)
                                            .background(Color.blue.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                    Text(amendment.title).font(.caption2).foregroundColor(.secondary)
                                    Text(amendment.heading).font(.subheadline).bold()
                                    Text("Tap to view agency details").font(.caption).foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            // External Link Fallback
                            if let urlString = amendment.url, let link = URL(string: urlString) {
                                Link(destination: link) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(amendment.date).font(.caption).bold().foregroundColor(.secondary)
                                        Text(amendment.title).font(.caption2).foregroundColor(.secondary)
                                        Text(amendment.heading).font(.subheadline).bold()
                                        HStack {
                                            Text("View on eCFR").font(.caption).foregroundColor(.blue)
                                            Image(systemName: "arrow.up.right.square").font(.caption).foregroundColor(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(amendment.date).font(.caption).bold().foregroundColor(.secondary)
                                    Text(amendment.title).font(.caption2).foregroundColor(.secondary)
                                    Text(amendment.heading).font(.subheadline).bold()
                                    Text("No link available").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } else if allRecords.isEmpty {
                 ContentUnavailableView("No Changes Recorded",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Pull to refresh to check for latest government-wide amendments."))
            }
        }
        .navigationTitle("What's Changed")
        .refreshable {
            await onRefresh?()
        }
    }
}
