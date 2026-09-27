import Foundation

/// Zdroj jednorázového snapshotu pro polling. Společný protokol pro Claude
/// (`UsageClient`) i Muse (`MuseUsageClient`), aby `PollingStore` šel použít
/// pro oba providery bez duplikace scheduling/backoff logiky.
public protocol SnapshotFetcher<Snapshot> {
    associatedtype Snapshot
    func fetch() async throws -> Snapshot
}

extension UsageClient: SnapshotFetcher {}
