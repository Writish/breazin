import Foundation
import SQLite3

actor GenerationJobStore {
    static let shared = GenerationJobStore()

    enum StoreError: LocalizedError {
        case sqlite(code: Int32, message: String)
        case corruptRecord(String)

        var errorDescription: String? {
            switch self {
            case .sqlite(let code, let message): "Generation database error \(code): \(message)"
            case .corruptRecord(let id): "Generation database record is corrupt: \(id)"
            }
        }
    }

    private let databaseURL: URL
    private var database: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(databaseURL: URL = AppConfiguration.current.applicationSupportDirectory.appendingPathComponent("generation-jobs.sqlite3")) {
        self.databaseURL = databaseURL
    }

    func create(_ job: NewGenerationJob) throws {
        try openIfNeeded()
        let now = Date().timeIntervalSince1970
        let placeholderJSON = try json(job.placeholderAssetIDs)
        try execute(
            """
            INSERT INTO generation_jobs (
                id, project_id, placeholder_asset_ids, provider_id, model, kind, state,
                idempotency_key, request_hash, cancel_requested, attempt_count, result_urls,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, '[]', ?, ?)
            ON CONFLICT(id) DO NOTHING
            """,
            [.text(job.id), .text(job.projectID), .text(placeholderJSON), .text(job.providerID),
             .text(job.model), .text(job.kind.rawValue), .text(GenerationJobState.preparing.rawValue),
             .text(job.idempotencyKey), .text(job.requestHash), .double(now), .double(now)]
        )
    }

    func job(id: String) throws -> GenerationJobRecord? {
        try openIfNeeded()
        return try queryJobs("SELECT * FROM generation_jobs WHERE id = ?", [.text(id)]).first
    }

    func recoverableJobs() throws -> [GenerationJobRecord] {
        try openIfNeeded()
        let terminals = [GenerationJobState.succeeded, .failed, .cancelled].map(\.rawValue)
        return try queryJobs(
            "SELECT * FROM generation_jobs WHERE state NOT IN (?, ?, ?) ORDER BY updated_at ASC",
            terminals.map(Binding.text)
        )
    }

    func jobs(projectID: String, includeTerminal: Bool = true) throws -> [GenerationJobRecord] {
        try openIfNeeded()
        if includeTerminal {
            return try queryJobs(
                "SELECT * FROM generation_jobs WHERE project_id = ? ORDER BY created_at DESC",
                [.text(projectID)]
            )
        }
        let terminals = [GenerationJobState.succeeded, .failed, .cancelled].map(\.rawValue)
        return try queryJobs(
            """
            SELECT * FROM generation_jobs
            WHERE project_id = ? AND state NOT IN (?, ?, ?)
            ORDER BY created_at DESC
            """,
            [.text(projectID)] + terminals.map(Binding.text)
        )
    }

    func recordProviderDetails(jobID: String, details: ProviderGenerationDetails?) throws {
        guard let details else { return }
        try transaction {
            guard let current = try job(id: jobID),
                  Self.shouldRecord(details, after: current.providerDetails) else { return }
            try execute(
                "UPDATE generation_jobs SET provider_details = ?, updated_at = ? WHERE id = ?",
                [
                    .text(try json(details)),
                    .double(Date().timeIntervalSince1970),
                    .text(jobID),
                ]
            )
        }
    }

    func recordOfflinePause(jobID: String) throws {
        try openIfNeeded()
        try execute(
            """
            UPDATE generation_jobs SET
                error_code = 'network_offline',
                error_message = 'Generation recovery is paused until the network is available.',
                updated_at = ?
            WHERE id = ? AND state NOT IN ('succeeded', 'failed', 'cancelled')
              AND error_code IS NOT 'network_offline'
            """,
            [.double(Date().timeIntervalSince1970), .text(jobID)]
        )
    }

    func scheduleRetry(
        jobID: String,
        at retryDate: Date,
        message: String,
        clearResultURLs: Bool = false
    ) throws {
        try openIfNeeded()
        try execute(
            """
            UPDATE generation_jobs SET
                retry_count = retry_count + 1,
                next_retry_at = ?,
                result_urls = CASE WHEN ? = 1 THEN '[]' ELSE result_urls END,
                error_code = 'recovery_retry_scheduled',
                error_message = ?,
                updated_at = ?
            WHERE id = ? AND state NOT IN ('succeeded', 'failed', 'cancelled')
            """,
            [
                .double(retryDate.timeIntervalSince1970),
                .int(clearResultURLs ? 1 : 0),
                .text(message),
                .double(Date().timeIntervalSince1970),
                .text(jobID),
            ]
        )
    }

    @discardableResult
    func transition(
        jobID: String,
        to requestedState: GenerationJobState,
        providerJobID: String? = nil,
        resultURLs: [String]? = nil,
        stagedOutputRelativePaths: [String]? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        nextRetryAt: Date? = nil,
        incrementAttempt: Bool = false,
        resetRetryCount: Bool = true
    ) throws -> GenerationJobRecord? {
        try transaction {
            guard let current = try job(id: jobID), !current.state.isTerminal else { return try job(id: jobID) }
            let completionStates: Set<GenerationJobState> = [.downloading, .finalizing, .succeeded]
            let state = current.cancelRequested && completionStates.contains(requestedState)
                ? .cancelled
                : requestedState
            guard Self.canTransition(from: current.state, to: state) else { return current }
            try execute(
                """
                UPDATE generation_jobs SET
                    state = ?,
                    provider_job_id = COALESCE(?, provider_job_id),
                    result_urls = COALESCE(?, result_urls),
                    staged_output_relative_paths = COALESCE(?, staged_output_relative_paths),
                    error_code = ?,
                    error_message = ?,
                    next_retry_at = ?,
                    retry_count = CASE WHEN ? = 1 THEN 0 ELSE retry_count END,
                    attempt_count = attempt_count + ?,
                    updated_at = ?
                WHERE id = ? AND state NOT IN ('succeeded', 'failed', 'cancelled')
                """,
                [.text(state.rawValue), providerJobID.map(Binding.text) ?? .null,
                 try resultURLs.map { .text(try json($0)) } ?? .null,
                 try stagedOutputRelativePaths.map { .text(try json($0)) } ?? .null,
                 errorCode.map(Binding.text) ?? .null, errorMessage.map(Binding.text) ?? .null,
                 nextRetryAt.map { .double($0.timeIntervalSince1970) } ?? .null,
                 .int(resetRetryCount ? 1 : 0), .int(incrementAttempt ? 1 : 0),
                 .double(Date().timeIntervalSince1970), .text(jobID)]
            )
            return try job(id: jobID)
        }
    }

    @discardableResult
    func requestCancellation(jobID: String) throws -> GenerationJobRecord? {
        try transaction {
            guard let current = try job(id: jobID) else { return nil }
            guard !current.state.isTerminal else { return current }
            let state: GenerationJobState = current.providerJobID == nil ? .cancelled : current.state
            try execute(
                "UPDATE generation_jobs SET cancel_requested = 1, state = ?, updated_at = ? WHERE id = ? AND state NOT IN ('succeeded', 'failed', 'cancelled')",
                [.text(state.rawValue), .double(Date().timeIntervalSince1970), .text(jobID)]
            )
            return try job(id: jobID)
        }
    }

    func createUpload(id: String, jobID: String, ordinal: Int, sourceAssetID: String, mediaKind: String) throws {
        try openIfNeeded()
        let now = Date().timeIntervalSince1970
        try execute(
            """
            INSERT INTO generation_uploads (
                id, job_id, ordinal, source_asset_id, media_kind, state, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO NOTHING
            """,
            [.text(id), .text(jobID), .int(ordinal), .text(sourceAssetID), .text(mediaKind),
             .text(GenerationUploadState.standardizing.rawValue), .double(now), .double(now)]
        )
    }

    func recordStandardizedUpload(
        id: String,
        relativePath: String,
        contentType: String,
        contentLength: Int64,
        checksumSHA256: String
    ) throws {
        try openIfNeeded()
        try execute(
            """
            UPDATE generation_uploads SET state = ?, standardized_relative_path = ?, content_type = ?,
                content_length = ?, checksum_sha256 = ?, updated_at = ? WHERE id = ?
            """,
            [.text(GenerationUploadState.requestingUpload.rawValue), .text(relativePath), .text(contentType),
             .int64(contentLength), .text(checksumSHA256), .double(Date().timeIntervalSince1970), .text(id)]
        )
    }

    func recordUploadHandle(id: String, uploadID: String, uploadHandle: String) throws {
        try openIfNeeded()
        try execute(
            "UPDATE generation_uploads SET state = ?, upload_id = ?, upload_handle = ?, updated_at = ? WHERE id = ?",
            [.text(GenerationUploadState.uploading.rawValue), .text(uploadID), .text(uploadHandle),
             .double(Date().timeIntervalSince1970), .text(id)]
        )
    }

    func recordUploaded(
        id: String,
        remoteURL: String,
        remoteURLExpiresAt: Date,
        objectExpiresAt: Date
    ) throws {
        try openIfNeeded()
        try execute(
            """
            UPDATE generation_uploads SET state = ?, remote_url = ?, remote_url_expires_at = ?,
                object_expires_at = ?, updated_at = ? WHERE id = ?
            """,
            [.text(GenerationUploadState.uploaded.rawValue), .text(remoteURL),
             .double(remoteURLExpiresAt.timeIntervalSince1970), .double(objectExpiresAt.timeIntervalSince1970),
             .double(Date().timeIntervalSince1970), .text(id)]
        )
    }

    func recordUploadFailure(id: String, code: String) throws {
        try openIfNeeded()
        try execute(
            "UPDATE generation_uploads SET state = ?, error_code = ?, updated_at = ? WHERE id = ?",
            [.text(GenerationUploadState.failed.rawValue), .text(code), .double(Date().timeIntervalSince1970), .text(id)]
        )
    }

    func recordUploadDeleted(id: String) throws {
        try openIfNeeded()
        try execute(
            """
            UPDATE generation_uploads SET state = ?, upload_handle = NULL, remote_url = NULL,
                remote_url_expires_at = NULL, object_expires_at = NULL, updated_at = ? WHERE id = ?
            """,
            [.text(GenerationUploadState.deleted.rawValue), .double(Date().timeIntervalSince1970), .text(id)]
        )
    }

    @discardableResult
    func expireUploads(now: Date = Date()) throws -> Int {
        try openIfNeeded()
        let statement = try prepare(
            """
            UPDATE generation_uploads SET state = ?, upload_handle = NULL, remote_url = NULL,
                remote_url_expires_at = NULL, updated_at = ?
            WHERE object_expires_at IS NOT NULL
              AND object_expires_at <= ?
              AND state NOT IN (?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(
            [
                .text(GenerationUploadState.expired.rawValue),
                .double(now.timeIntervalSince1970),
                .double(now.timeIntervalSince1970),
                .text(GenerationUploadState.expired.rawValue),
                .text(GenerationUploadState.deleted.rawValue),
            ],
            to: statement
        )
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else { throw sqliteError(result) }
        return Int(sqlite3_changes(database))
    }

    func uploads(jobID: String) throws -> [GenerationUploadRecord] {
        try openIfNeeded()
        let statement = try prepare("SELECT * FROM generation_uploads WHERE job_id = ? ORDER BY ordinal ASC")
        defer { sqlite3_finalize(statement) }
        try bind([.text(jobID)], to: statement)
        var records: [GenerationUploadRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW { records.append(try decodeUpload(statement)) }
        return records
    }

    private func openIfNeeded() throws {
        guard database == nil else { return }
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database"
            if let connection { sqlite3_close(connection) }
            throw StoreError.sqlite(code: result, message: message)
        }
        database = connection
        do {
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA busy_timeout = 5000")
            try migrate()
        } catch {
            sqlite3_close(connection)
            database = nil
            throw error
        }
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS generation_jobs (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                placeholder_asset_ids TEXT NOT NULL,
                provider_id TEXT NOT NULL,
                model TEXT NOT NULL,
                kind TEXT NOT NULL,
                state TEXT NOT NULL,
                idempotency_key TEXT NOT NULL UNIQUE,
                provider_job_id TEXT,
                request_hash TEXT NOT NULL,
                cancel_requested INTEGER NOT NULL DEFAULT 0,
                attempt_count INTEGER NOT NULL DEFAULT 0,
                retry_count INTEGER NOT NULL DEFAULT 0,
                next_retry_at REAL,
                result_urls TEXT NOT NULL DEFAULT '[]',
                staged_output_relative_paths TEXT NOT NULL DEFAULT '[]',
                provider_details TEXT,
                error_code TEXT,
                error_message TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS generation_uploads (
                id TEXT PRIMARY KEY,
                job_id TEXT NOT NULL REFERENCES generation_jobs(id) ON DELETE CASCADE,
                ordinal INTEGER NOT NULL,
                source_asset_id TEXT NOT NULL,
                media_kind TEXT NOT NULL,
                state TEXT NOT NULL,
                standardized_relative_path TEXT,
                content_type TEXT,
                content_length INTEGER,
                checksum_sha256 TEXT,
                upload_id TEXT,
                upload_handle TEXT,
                remote_url TEXT,
                remote_url_expires_at REAL,
                object_expires_at REAL,
                error_code TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                UNIQUE(job_id, ordinal)
            )
            """
        )
        if try !hasStagedOutputColumn() {
            try execute(
                "ALTER TABLE generation_jobs ADD COLUMN staged_output_relative_paths TEXT NOT NULL DEFAULT '[]'"
            )
        }
        if try !hasColumn("provider_details", in: "generation_jobs") {
            try execute("ALTER TABLE generation_jobs ADD COLUMN provider_details TEXT")
        }
        if try !hasColumn("retry_count", in: "generation_jobs") {
            try execute(
                "ALTER TABLE generation_jobs ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0"
            )
        }
        try execute("CREATE INDEX IF NOT EXISTS idx_generation_jobs_state ON generation_jobs(state, updated_at)")
        try execute("CREATE INDEX IF NOT EXISTS idx_generation_jobs_retry ON generation_jobs(next_retry_at)")
        try execute("CREATE INDEX IF NOT EXISTS idx_generation_uploads_job ON generation_uploads(job_id, ordinal)")
        try execute("PRAGMA user_version = 4")
    }

    private func hasStagedOutputColumn() throws -> Bool {
        try hasColumn("staged_output_relative_paths", in: "generation_jobs")
    }

    private func hasColumn(_ column: String, in table: String) throws -> Bool {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column { return true }
        }
        return false
    }

    private func queryJobs(_ sql: String, _ bindings: [Binding]) throws -> [GenerationJobRecord] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        var records: [GenerationJobRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW { records.append(try decodeJob(statement)) }
        return records
    }

    private func decodeJob(_ statement: OpaquePointer) throws -> GenerationJobRecord {
        guard let id = string(statement, "id"),
              let projectID = string(statement, "project_id"),
              let placeholdersJSON = string(statement, "placeholder_asset_ids"),
              let providerID = string(statement, "provider_id"),
              let model = string(statement, "model"),
              let kindValue = string(statement, "kind"), let kind = ProviderGenerationKind(rawValue: kindValue),
              let stateValue = string(statement, "state"), let state = GenerationJobState(rawValue: stateValue),
              let idempotencyKey = string(statement, "idempotency_key"),
              let requestHash = string(statement, "request_hash"),
              let resultsJSON = string(statement, "result_urls"),
              let stagedOutputsJSON = string(statement, "staged_output_relative_paths")
        else { throw StoreError.corruptRecord("generation_job") }
        return GenerationJobRecord(
            id: id, projectID: projectID, placeholderAssetIDs: try value([String].self, placeholdersJSON),
            providerID: providerID, model: model, kind: kind, state: state,
            idempotencyKey: idempotencyKey, providerJobID: string(statement, "provider_job_id"),
            requestHash: requestHash, cancelRequested: integer(statement, "cancel_requested") != 0,
            attemptCount: Int(integer(statement, "attempt_count")),
            retryCount: Int(integer(statement, "retry_count")),
            nextRetryAt: date(statement, "next_retry_at"), resultURLs: try value([String].self, resultsJSON),
            stagedOutputRelativePaths: try value([String].self, stagedOutputsJSON),
            providerDetails: try string(statement, "provider_details").map {
                try value(ProviderGenerationDetails.self, $0)
            },
            errorCode: string(statement, "error_code"), errorMessage: string(statement, "error_message"),
            createdAt: date(statement, "created_at") ?? .distantPast,
            updatedAt: date(statement, "updated_at") ?? .distantPast
        )
    }

    private func decodeUpload(_ statement: OpaquePointer) throws -> GenerationUploadRecord {
        guard let id = string(statement, "id"), let jobID = string(statement, "job_id"),
              let sourceID = string(statement, "source_asset_id"), let kind = string(statement, "media_kind"),
              let stateValue = string(statement, "state"), let state = GenerationUploadState(rawValue: stateValue)
        else { throw StoreError.corruptRecord("generation_upload") }
        let length = nullableInteger(statement, "content_length")
        return GenerationUploadRecord(
            id: id, jobID: jobID, ordinal: Int(integer(statement, "ordinal")), sourceAssetID: sourceID,
            mediaKind: kind, state: state, standardizedRelativePath: string(statement, "standardized_relative_path"),
            contentType: string(statement, "content_type"), contentLength: length,
            checksumSHA256: string(statement, "checksum_sha256"), uploadID: string(statement, "upload_id"),
            uploadHandle: string(statement, "upload_handle"), remoteURL: string(statement, "remote_url"),
            remoteURLExpiresAt: date(statement, "remote_url_expires_at"), objectExpiresAt: date(statement, "object_expires_at"),
            errorCode: string(statement, "error_code"), createdAt: date(statement, "created_at") ?? .distantPast,
            updatedAt: date(statement, "updated_at") ?? .distantPast
        )
    }

    private enum Binding {
        case text(String), int(Int), int64(Int64), double(Double), null
    }

    private func execute(_ sql: String, _ bindings: [Binding] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else { throw sqliteError(result) }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw StoreError.sqlite(code: SQLITE_MISUSE, message: "Database is not open") }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw sqliteError(result) }
        return statement
    }

    private func bind(_ bindings: [Binding], to statement: OpaquePointer) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32 = switch binding {
            case .text(let value): sqlite3_bind_text(statement, index, value, -1, Self.transient)
            case .int(let value): sqlite3_bind_int64(statement, index, Int64(value))
            case .int64(let value): sqlite3_bind_int64(statement, index, value)
            case .double(let value): sqlite3_bind_double(statement, index, value)
            case .null: sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw sqliteError(result) }
        }
    }

    private func transaction<T>(_ operation: () throws -> T) throws -> T {
        try openIfNeeded()
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try operation()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func sqliteError(_ code: Int32) -> StoreError {
        StoreError.sqlite(code: code, message: database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error")
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func value<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    private func column(_ statement: OpaquePointer, _ name: String) -> Int32 {
        for index in 0..<sqlite3_column_count(statement) {
            if String(cString: sqlite3_column_name(statement, index)) == name { return index }
        }
        return -1
    }

    private func string(_ statement: OpaquePointer, _ name: String) -> String? {
        let index = column(statement, name)
        guard index >= 0, sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func integer(_ statement: OpaquePointer, _ name: String) -> Int64 {
        sqlite3_column_int64(statement, column(statement, name))
    }

    private func nullableInteger(_ statement: OpaquePointer, _ name: String) -> Int64? {
        let index = column(statement, name)
        guard index >= 0, sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private func date(_ statement: OpaquePointer, _ name: String) -> Date? {
        let index = column(statement, name)
        guard index >= 0, sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private static func canTransition(from current: GenerationJobState, to next: GenerationJobState) -> Bool {
        if current == next { return true }
        if next == .failed || next == .cancelled || next == .needsAttention { return !current.isTerminal }
        return switch current {
        case .preparing: next == .submitting
        case .submitting: [.queued, .running, .downloading].contains(next)
        case .queued: [.running, .downloading].contains(next)
        case .running: next == .downloading
        case .downloading: [.finalizing, .succeeded].contains(next)
        case .finalizing: next == .succeeded
        case .needsAttention: [.running, .downloading].contains(next)
        case .succeeded, .failed, .cancelled: false
        }
    }

    private static func shouldRecord(
        _ incoming: ProviderGenerationDetails,
        after current: ProviderGenerationDetails?
    ) -> Bool {
        guard let current else { return true }
        let rank: (ProviderGenerationState) -> Int = {
            switch $0 {
            case .queued: 0
            case .running, .needsAttention: 1
            case .downloading, .succeeded, .failed, .cancelled: 2
            }
        }
        guard rank(incoming.status) >= rank(current.status) else { return false }
        if let incomingUpdated = incoming.providerUpdatedAt,
           let currentUpdated = current.providerUpdatedAt {
            return incomingUpdated >= currentUpdated
        }
        return incoming.checkedAt >= current.checkedAt
    }
}
