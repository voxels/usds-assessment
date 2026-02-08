import Foundation
import SwiftData
import FirebaseDatabase

/// Thread-safe sync engine. Uses its own ModelContext to avoid data races.
actor SyncService: ModelActor {
    let modelContainer: ModelContainer
    let modelExecutor: any ModelExecutor
    private let dataService: DataServiceProtocol
    
    // Dependencies
    private var agenciesRef: DatabaseReference?
    private var statsRef: DatabaseReference?
    
    static let prioritySlugs: Set<String> = [
        "health-and-human-services-department",
        "social-security-administration",
        "treasury-department",
        "defense-department",
        "veterans-affairs-department"
    ]
    
    struct SyncResult: Sendable {
        let total: Int
        let updated: Int
        let inserted: Int
    }
    
    @MainActor
    static func makeDefault() -> SyncService {
        let schema = Schema([Agency.self, AgencySummary.self, ChecksumRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            return SyncService(container: container, dataService: NetworkService.shared)
        } catch {
            fatalError("Could not create ModelContainer for default SyncService: \(error)")
        }
    }
    
    init(container: ModelContainer, dataService: DataServiceProtocol) {
        self.modelContainer = container
        let context = ModelContext(container)
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: context)
        self.dataService = dataService
    }
    
    // MARK: - Real-Time Listeners
    
    func startListening() {
        let db = Database.database().reference()
        
        // Listen for Agencies
        agenciesRef = db.child("agencies")
        agenciesRef?.observe(.value) { [weak self] snapshot in
            guard let self = self else { return }
            guard let value = snapshot.value as? [[String: Any]] else { return }
            
            // Move decoding to Task to avoid blocking callback and potential isolation issues
            Task {
                do {
                    let data = try JSONSerialization.data(withJSONObject: value)
                    let agencies = try JSONDecoder().decode([AgencyTransfer].self, from: data)
                    await self.performUpdate(with: agencies)
                } catch {
                    print("Sync Error (Agencies Realtime): \(error)")
                }
            }
        }
        
        // Listen for Stats
        statsRef = db.child("stats")
        statsRef?.observe(.value) { snapshot in
            guard let value = snapshot.value as? [String: Any] else { return }
            
            Task {
                do {
                    let data = try JSONSerialization.data(withJSONObject: value)
                    let stats = try await MainActor.run {
                        try JSONDecoder().decode(StatsTransfer.self, from: data)
                    }
                    
                    // Dispatch to Main Actor for notification
                    await MainActor.run {
                        NotificationCenter.default.post(name: .didReceiveRemoteStats, object: nil, userInfo: ["stats": stats])
                    }
                } catch {
                    print("Sync Error (Stats Realtime): \(error)")
                }
            }
        }
    }
    
    func stopListening() {
        agenciesRef?.removeAllObservers()
        statsRef?.removeAllObservers()
    }
    
    // MARK: - Manual Sync
    
    @discardableResult
    func sync() async throws -> Int {
        let transfers = try await dataService.fetchAgencies()
        let result = performUpdate(with: transfers)
        return result.updated + result.inserted
    }
    
    // MARK: - Core Update Logic
    
    @discardableResult
    private func performUpdate(with transfers: [AgencyTransfer]) -> SyncResult {
        let context = modelContext
        var updated = 0, inserted = 0
        
        // Fetch all existing agencies once to optimize lookups
        let existingAgencies = (try? context.fetch(FetchDescriptor<Agency>()))?
            .reduce(into: [String: Agency]()) { $0[$1.slug] = $1 } ?? [:]
        
        for transfer in transfers {
            let slug = transfer.slug
            let isPriority = Self.prioritySlugs.contains(slug)
            
            if let existing = existingAgencies[slug] {
                // Check if update is needed (checksum or metrics)
                // We access camelCase properties on Transfer now
                if existing.checksum != transfer.checksum ||
                   existing.wordCountProxy != transfer.wordCountProxy ||
                   existing.analyzedAt != transfer.analyzedAt {
                    
                    // Log Checksum Change
                    if existing.checksum != transfer.checksum {
                        context.insert(ChecksumRecord(
                            agencySlug: existing.slug,
                            agencyName: existing.name,
                            previousChecksum: existing.checksum,
                            newChecksum: transfer.checksum ?? "N/A"
                        ))
                    }
                    
                    // Use model's update method
                    existing.update(from: transfer)
                    updated += 1
                }
                
                // Ensure priority favorites
                if isPriority && !existing.isFavorite { existing.isFavorite = true }
                
            } else {
                // Insert New
                let newAgency = Agency(from: transfer)
                newAgency.isFavorite = isPriority
                
                context.insert(newAgency)
                inserted += 1
            }
        }
        
        if context.hasChanges {
            try? context.save()
        }
        
        return SyncResult(total: transfers.count, updated: updated, inserted: inserted)
    }
}

extension Notification.Name {
    static let didReceiveRemoteStats = Notification.Name("didReceiveRemoteStats")
}
