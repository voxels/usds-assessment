import SwiftUI
import SwiftData

struct ChangesView: View {
    @Query(sort: [SortDescriptor(\ChecksumRecord.recordedAt, order: .reverse)])
    private var allRecords: [ChecksumRecord]
    @Binding var selectedAgency: Agency?
    @Query private var agencies: [Agency]

    var todayRecords: [ChecksumRecord] {
        let calendar = Calendar.current
        return allRecords.filter { calendar.isDateInToday($0.recordedAt) }
    }

    var onRefresh: (() async -> Void)?

    var groupedByDate: [(String, [ChecksumRecord])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let grouped = Dictionary(grouping: allRecords) { formatter.string(from: $0.recordedAt) }
        return grouped.sorted { $0.value.first!.recordedAt > $1.value.first!.recordedAt }
    }

    var body: some View {
        List {
            // Today's Changes
            if !todayRecords.isEmpty {
                Section("Changed Since Last Launch") {
                    ForEach(todayRecords, id: \.agencySlug) { record in
                        Button {
                            selectedAgency = agencies.first { $0.slug == record.agencySlug }
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
                    }
                }
            }

            // Full Timeline
            if !allRecords.isEmpty {
                ForEach(groupedByDate, id: \.0) { date, records in
                    Section(date) {
                        ForEach(records, id: \.agencySlug) { record in
                            Button {
                                selectedAgency = agencies.first { $0.slug == record.agencySlug }
                            } label: {
                                Label(record.agencyName, systemImage: "doc.badge.clock")
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Changes Recorded",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Changes will appear here as agency data is updated during synchronization."))
            }
        }
        .navigationTitle("What's Changed")
        .refreshable {
            await onRefresh?()
        }
    }
}
