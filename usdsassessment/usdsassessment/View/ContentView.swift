import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var viewModel = AppViewModel()

    var body: some View {
        @Bindable var vm = viewModel

        NavigationSplitView {
            SidebarView(selectedDepartment: $vm.selectedDepartment,
                        selectedAgency: $vm.selectedAgency,
                        activeTool: $vm.activeTool)
        } content: {
            if let tool = viewModel.activeTool, tool == .changes {
                ChangesView(selectedAgency: $vm.selectedAgency, onRefresh: {
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

    @ViewBuilder
    private var detailContent: some View {
        if let agency = viewModel.selectedAgency {
            AgencyDetailView(agency: agency, dataService: NetworkService.shared)
                .id(agency.persistentModelID) // Force recreation when selection changes
        } else {
            GlobalDashboardView(activeTool: $viewModel.activeTool)
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
