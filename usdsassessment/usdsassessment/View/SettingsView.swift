import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showConfirmation = false
    @State private var isClearing = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Data Management") {
                    Button(role: .destructive) {
                        showConfirmation = true
                    } label: {
                        if isClearing {
                            ProgressView()
                        } else {
                            Label("Clear Local Cache", systemImage: "trash")
                        }
                    }
                    .disabled(isClearing)
                }
                
                Section {
                    Text("This will delete all downloaded agencies and AI summaries. They will be re-synced from the server on next launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Clear All Data?", isPresented: $showConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                     Task { await clearCache() }
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
    
    @MainActor
    private func clearCache() async {
        isClearing = true
        do {
            try modelContext.delete(model: Agency.self)
            try modelContext.delete(model: AgencySummary.self) // Should cascade, but being safe
            // Also clear generic checksums if they exist as separate models
             try modelContext.delete(model: ChecksumRecord.self)
             
            try modelContext.save()
            print("✅ Cache cleared successfully")
            
            // Optional: dramatic effect or delay to let UI update
            try? await Task.sleep(for: .seconds(1))
            dismiss()
        } catch {
            print("❌ Failed to clear cache: \(error)")
        }
        isClearing = false
    }
}
