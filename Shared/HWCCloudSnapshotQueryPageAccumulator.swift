import Foundation

/// A CloudKit query page is complete only when every matched record was read.
/// Returning the successful subset would make Recovery falsely render empty.
struct HWCCloudSnapshotQueryPageAccumulator<Record> {
    private var records: [Record] = []
    private var firstFailure: Error?

    mutating func record(_ result: Result<Record, Error>) {
        switch result {
        case .success(let record):
            records.append(record)
        case .failure(let error):
            if firstFailure == nil {
                firstFailure = error
            }
        }
    }

    func validatedRecords() throws -> [Record] {
        if let firstFailure {
            throw firstFailure
        }
        return records
    }
}

/// Accumulates a complete record-zone history stream. A later record callback
/// replaces the earlier value for the same ID, while deletion callbacks remove
/// that ID across page boundaries. Any failed record callback invalidates the
/// whole listing so Recovery cannot render a misleading partial history.
struct HWCCloudSnapshotZoneHistoryAccumulator<ID: Hashable, Record> {
    private var records: [ID: Record] = [:]
    private var firstFailure: Error?

    mutating func record(_ result: Result<Record, Error>, id: ID) {
        switch result {
        case .success(let record):
            records[id] = record
        case .failure(let error):
            if firstFailure == nil {
                firstFailure = error
            }
        }
    }

    mutating func delete(id: ID) {
        records[id] = nil
    }

    func validatedRecords() throws -> [Record] {
        if let firstFailure {
            throw firstFailure
        }
        return Array(records.values)
    }
}
