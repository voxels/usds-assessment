import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var viewModel = AppViewModel()

    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedDepartment: $vm.selectedDepartment,
                        selectedAgency: $vm.selectedAgency,
                        activeTool: $vm.activeTool,
                        globalAmendments: viewModel.globalAmendments,
                        onRefresh: { await viewModel.syncOnLaunch() })
        } content: {
            if let tool = viewModel.activeTool, tool == .changes {
                ChangesView(selectedAgency: $vm.selectedAgency,
                            globalAmendments: viewModel.globalAmendments,
                            onRefresh: {
                    await viewModel.syncOnLaunch()
                })
            } else if viewModel.selectedDepartment != nil {
                AgencyListView(department: viewModel.selectedDepartment,
                               selectedAgency: $vm.selectedAgency)
            } else {
                ContentUnavailableView("Select a Department",
                    systemImage: "building.columns",
                    description: Text("Choose a department or use the tools above."))
            }
        } detail: {
            detailContent
        }
        .task {
            // Configure with the shared container
            viewModel.configure(dataService: NetworkService.shared)
            await viewModel.syncOnLaunch()
        }
        .overlay { syncOverlay }
        .alert("Sync Error",
               isPresented: .init(get: { viewModel.syncError != nil },
                                  set: { _ in viewModel.syncError = nil })) {
            Button("OK") { }
        } message: {
            Text(viewModel.syncError ?? "")
        }
    }

    @Query private var allAgencies: [Agency] // Add Query to access data

    @ViewBuilder
    private var detailContent: some View {
        if let agency = viewModel.selectedAgency {
            AgencyDetailView(agency: agency, dataService: NetworkService.shared)
                .id(agency.persistentModelID) // Force recreation when selection changes
        } else if let department = viewModel.selectedDepartment {
            // Filter agencies for this department
            let deptAgencies = allAgencies.filter {
                $0.parentAgencyName == department.name || $0.slug == department.slug
            }.sorted { $0.name < $1.name }
            
            ScrollView {
                DepartmentDashboardView(department: department, agencies: deptAgencies, selectedAgency: $viewModel.selectedAgency)
                    .padding()
            }
            .navigationTitle(department.shortName ?? department.name)
        } else {
            GlobalDashboardView(activeTool: $viewModel.activeTool, selectedAgency: $viewModel.selectedAgency)
        }
    }

    @ViewBuilder
    private var syncOverlay: some View {
        if viewModel.isSyncing {
            ZStack {
                Color.black.opacity(0.2).ignoresSafeArea()
                ProgressView("Synchronizing Government Records...")
                    .padding().background(.regularMaterial).cornerRadius(10)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Agency.self, AgencySummary.self, ChecksumRecord.self], inMemory: true)
}
