import SwiftUI
import SwiftData

enum DepartmentSort: String, CaseIterable {
    case alphabetical = "A-Z"
    case recentChanges = "Recent"
    case footprint = "Size"
}

enum SidebarTool: String, CaseIterable, Identifiable {
    case overview = "Regulatory Overview"
    case changes = "What's Changed"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: return "chart.bar.doc.horizontal"
        case .changes: return "clock.arrow.circlepath"
        }
    }
}

struct SidebarView: View {
    @Query(filter: #Predicate<Agency> { $0.parentAgencyName == nil }, sort: [SortDescriptor(\Agency.name)])
    private var allDepartments: [Agency]

    @Binding var selectedDepartment: Agency?
    @Binding var selectedAgency: Agency?
    @Binding var activeTool: SidebarTool?
    
    // Dependencies for Tool Views
    var globalAmendments: [AmendmentTransfer]
    var onRefresh: () async -> Void

    @State private var sortOrder: DepartmentSort = .alphabetical
    @State private var searchText = ""
    @State private var showSettings = false
    @Query private var allAgencies: [Agency] // Needed for global search

    var favorites: [Agency] {
        sortedDepartments(allDepartments.filter { $0.isFavorite && $0.parentAgencyName == nil })
    }

    var otherDepartments: [Agency] {
        sortedDepartments(allDepartments.filter { !$0.isFavorite && $0.parentAgencyName == nil })
    }
    
    var searchResults: [Agency] {
         guard !searchText.isEmpty else { return [] }
         let query = searchText.lowercased()
         return allAgencies.filter { agency in
             if agency.name.lowercased().contains(query) { return true }
             if agency.shortName?.lowercased().contains(query) == true { return true }
             return false
         }
    }

    var body: some View {
        List {
            // Search Results
            if !searchText.isEmpty {
                Section("Search Results") {
                    if searchResults.isEmpty {
                        Text("No results found").foregroundColor(.secondary)
                    } else {
                        ForEach(searchResults) { agency in
                             NavigationLink(value: NavigationDestination.agencyDetail(agency)) {
                                 VStack(alignment: .leading) {
                                     Text(agency.name).font(.headline)
                                     if let p = agency.parentAgencyName {
                                         Text(p).font(.caption).foregroundColor(.secondary)
                                     }
                                 }
                             }
                        }
                    }
                }
            } else {
                // Tools Section
                Section("Insights") {
                    ForEach(SidebarTool.allCases) { tool in
                        NavigationLink(value: NavigationDestination.tool(tool)) {
                            Label(tool.rawValue, systemImage: tool.icon)
                        }
                    }
                }

                // Sort Picker
                Section {
                    Picker("Sort By", selection: $sortOrder) {
                        ForEach(DepartmentSort.allCases, id: \.self) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Favorites
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { dept in
                            departmentRow(dept)
                        }
                    }
                }

                // All Departments
                Section("All Departments") {
                    ForEach(otherDepartments) { dept in
                        departmentRow(dept)
                    }
                }
            }
        }
        .navigationTitle("Departments")
        .searchable(text: $searchText, placement:.navigationBarDrawer(displayMode: .always), prompt: "Search Agencies")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
             SettingsView()
        }
        .navigationDestination(for: NavigationDestination.self) { dest in
            switch dest {
            case .agencyDetail(let agency):
                AgencyDetailView(agency: agency, dataService: NetworkService.shared)
                    .onAppear {
                        selectedAgency = agency
                        selectedDepartment = nil
                        activeTool = nil
                    }
            case .departmentList(let dept):
                AgencyListView(department: dept, selectedAgency: $selectedAgency)
                    .onAppear {
                        selectedDepartment = dept
                        activeTool = nil
                    }
            case .tool(let tool):
                if tool == .changes {
                    ChangesView(selectedAgency: $selectedAgency,
                                globalAmendments: globalAmendments,
                                onRefresh: onRefresh)
                    .onAppear {
                        activeTool = tool
                        selectedDepartment = nil
                        selectedAgency = nil // changes view handles agency selection differently?
                    }
                } else {
                    // Overview
                    GlobalDashboardView(activeTool: $activeTool, selectedAgency: $selectedAgency)
                        .onAppear {
                            activeTool = tool
                            selectedDepartment = nil
                        }
                }
            }
        }
    }

    private func sortedDepartments(_ depts: [Agency]) -> [Agency] {
        switch sortOrder {
        case .alphabetical:
            return depts.sorted { $0.name < $1.name }
        case .recentChanges:
            return depts.sorted { ($0.latestAmendedOn ?? "") > ($1.latestAmendedOn ?? "") }
        case .footprint:
            return depts.sorted { $0.wordCountProxy > $1.wordCountProxy }
        }
    }
 
    private func departmentRow(_ department: Agency) -> some View {
        NavigationLink(value: NavigationDestination.departmentList(department)) {
            HStack {
                Label(department.name,
                      systemImage: department.isFavorite ? "star.fill" : "building.columns")
                Spacer()
                if sortOrder == .recentChanges, let date = department.latestAmendedOn {
                    Text(date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if sortOrder == .footprint {
                    Text("\(department.wordCountProxy)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button {
                department.isFavorite.toggle()
            } label: {
                Label(department.isFavorite ? "Unfavorite" : "Favorite",
                      systemImage: department.isFavorite ? "star.slash" : "star")
            }
            .tint(department.isFavorite ? .gray : .yellow)
        }
        .contextMenu {
            Button {
                department.isFavorite.toggle()
            } label: {
                Label(department.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: department.isFavorite ? "star.slash" : "star")
            }
        }
    }
}

enum NavigationDestination: Hashable {
    case agencyDetail(Agency)
    case departmentList(Agency)
    case tool(SidebarTool)
}
