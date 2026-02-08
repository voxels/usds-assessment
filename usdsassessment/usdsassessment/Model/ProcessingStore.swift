import SwiftUI

@Observable
final class ProcessingStore {
    var processingAgencies: Set<String> = []

    func startProcessing(_ slug: String) {
        processingAgencies.insert(slug)
    }

    func stopProcessing(_ slug: String) {
        processingAgencies.remove(slug)
    }

    func isProcessing(_ slug: String) -> Bool {
        processingAgencies.contains(slug)
    }
}
