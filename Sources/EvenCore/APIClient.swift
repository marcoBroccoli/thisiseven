import Foundation

public enum APIEnvironment: Sendable {
    /// Simulator / same-machine development.
    case localhost
    /// LAN / tailnet devices via the Caddy route.
    case home

    public var baseURL: URL {
        switch self {
        case .localhost: return URL(string: "http://localhost:8091")!
        case .home: return URL(string: "http://even-api.home")!
        }
    }

    public static var current: APIEnvironment {
        #if targetEnvironment(simulator)
        return .localhost
        #else
        return .home
        #endif
    }
}

public enum APIError: Error, LocalizedError {
    case http(status: Int, code: String, message: String)
    case transport(Error)
    case decoding(Error)
    case notSignedIn

    public var errorDescription: String? {
        switch self {
        case let .http(_, _, message): return message
        case .transport: return "Can't reach the house server."
        case .decoding: return "Unexpected server reply."
        case .notSignedIn: return "Signed out."
        }
    }

    public var code: String? {
        if case let .http(_, code, _) = self { return code }
        return nil
    }
}

/// Async client for the evend API. Auth token comes from the provider closure
/// so the session layer stays in charge of refresh.
public final class EvenAPIClient: @unchecked Sendable {
    public let environment: APIEnvironment
    private let session: URLSession
    private let tokenProvider: () async throws -> String?

    public init(environment: APIEnvironment = .current,
                session: URLSession = .shared,
                tokenProvider: @escaping () async throws -> String?) {
        self.environment = environment
        self.session = session
        self.tokenProvider = tokenProvider
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: s) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Bad date: \(s)"))
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: Requests

    public func get<T: Decodable>(_ path: String) async throws -> T {
        try await request("GET", path, body: Optional<Int>.none)
    }

    public func post<T: Decodable, B: Encodable>(_ path: String, _ body: B?) async throws -> T {
        try await request("POST", path, body: body)
    }

    public func post<T: Decodable>(_ path: String) async throws -> T {
        try await request("POST", path, body: Optional<Int>.none)
    }

    public func patch<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        try await request("PATCH", path, body: body)
    }

    public func put<T: Decodable, B: Encodable>(_ path: String, _ body: B) async throws -> T {
        try await request("PUT", path, body: body)
    }

    public func delete(_ path: String) async throws {
        struct Empty: Decodable {}
        let _: Empty? = try? await request("DELETE", path, body: Optional<Int>.none)
    }

    private func request<T: Decodable, B: Encodable>(_ method: String,
                                                     _ path: String,
                                                     body: B?) async throws -> T {
        var req = URLRequest(url: environment.baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 15
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.encoder.encode(body)
        }
        if let token = try await tokenProvider() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if let apiError = try? Self.decoder.decode(APIErrorBody.self, from: data) {
                throw APIError.http(status: status,
                                    code: apiError.error.code,
                                    message: apiError.error.message)
            }
            throw APIError.http(status: status, code: "http_\(status)",
                                message: "Server error (\(status)).")
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

// MARK: - Typed endpoints

public extension EvenAPIClient {
    func me() async throws -> MeResponse { try await get("v1/me") }

    func createHousehold(name: String, displayName: String) async throws -> Household {
        struct B: Encodable { let name: String; let displayName: String }
        return try await post("v1/households", B(name: name, displayName: displayName))
    }

    func joinHousehold(inviteCode: String, displayName: String) async throws -> Household {
        struct B: Encodable { let inviteCode: String; let displayName: String }
        return try await post("v1/households/join", B(inviteCode: inviteCode, displayName: displayName))
    }

    func summary() async throws -> Summary { try await get("v1/summary") }

    struct TaskDraftBody: Encodable {
        public var title: String
        public var section: TaskSection
        public var ownerMemberId: UUID
        public var weight: Int
        public var recurrence: Recurrence
        public var dueOn: String?
        public init(title: String, section: TaskSection, ownerMemberId: UUID,
                    weight: Int, recurrence: Recurrence, dueOn: String? = nil) {
            self.title = title
            self.section = section
            self.ownerMemberId = ownerMemberId
            self.weight = weight
            self.recurrence = recurrence
            self.dueOn = dueOn
        }
    }

    func createTask(_ body: TaskDraftBody) async throws -> HouseholdTask {
        try await post("v1/tasks", body)
    }

    func updateTask(id: UUID, _ body: TaskDraftBody) async throws -> HouseholdTask {
        try await patch("v1/tasks/\(id.uuidString.lowercased())", body)
    }

    func deleteTask(id: UUID) async throws {
        try await delete("v1/tasks/\(id.uuidString.lowercased())")
    }

    func toggleTask(id: UUID) async throws -> HouseholdTask {
        try await post("v1/tasks/\(id.uuidString.lowercased())/toggle")
    }

    func pendingDrafts() async throws -> [Draft] { try await get("v1/drafts?status=pending") }

    struct ProposeDraftBody: Encodable {
        public var fromLabel: String
        public var subject: String
        public var summary: String?
        public var urgency: Int
        public var ownerMemberId: UUID?
        public var amountCents: Int?
        public var dueOn: String?
        public var reminder: DraftReminder?
        public init(fromLabel: String, subject: String, summary: String? = nil,
                    urgency: Int, ownerMemberId: UUID? = nil, amountCents: Int? = nil,
                    dueOn: String? = nil, reminder: DraftReminder? = nil) {
            self.fromLabel = fromLabel
            self.subject = subject
            self.summary = summary
            self.urgency = urgency
            self.ownerMemberId = ownerMemberId
            self.amountCents = amountCents
            self.dueOn = dueOn
            self.reminder = reminder
        }
    }

    func proposeDraft(_ body: ProposeDraftBody) async throws -> Draft {
        try await post("v1/drafts", body)
    }

    struct DraftPatchBody: Encodable {
        public var title: String?
        public var ownerMemberId: UUID?
        public var amountCents: Int?
        public var dueOn: String?
        public var reminder: DraftReminder?
        public init(title: String? = nil, ownerMemberId: UUID? = nil,
                    amountCents: Int? = nil, dueOn: String? = nil,
                    reminder: DraftReminder? = nil) {
            self.title = title
            self.ownerMemberId = ownerMemberId
            self.amountCents = amountCents
            self.dueOn = dueOn
            self.reminder = reminder
        }
    }

    func updateDraft(id: UUID, _ body: DraftPatchBody) async throws -> Draft {
        try await patch("v1/drafts/\(id.uuidString.lowercased())", body)
    }

    struct ApproveResponse: Decodable {
        public var draft: Draft
        public var task: HouseholdTask
    }

    func approveDraft(id: UUID) async throws -> ApproveResponse {
        try await post("v1/drafts/\(id.uuidString.lowercased())/approve")
    }

    func dismissDraft(id: UUID) async throws -> Draft {
        try await post("v1/drafts/\(id.uuidString.lowercased())/dismiss")
    }

    func money() async throws -> Money { try await get("v1/money") }

    struct ExpenseBody: Encodable {
        public var title: String
        public var amountCents: Int
        public var paidByMemberId: UUID
        public var incurredOn: String
        public init(title: String, amountCents: Int, paidByMemberId: UUID, incurredOn: String) {
            self.title = title
            self.amountCents = amountCents
            self.paidByMemberId = paidByMemberId
            self.incurredOn = incurredOn
        }
    }

    func addExpense(_ body: ExpenseBody) async throws -> Expense {
        try await post("v1/expenses", body)
    }

    func settle() async throws -> Money { try await post("v1/settle") }

    func resetSummary() async throws -> ResetSummary { try await get("v1/reset") }

    func setMyAppreciation(body: String?, said: Bool) async throws -> Appreciation {
        struct B: Encodable { let body: String?; let said: Bool }
        return try await put("v1/appreciations/mine", B(body: body, said: said))
    }

    func proposeTrade(taskId: UUID) async throws -> Trade {
        struct B: Encodable { let taskId: UUID }
        return try await post("v1/trades", B(taskId: taskId))
    }

    func acceptTrade(id: UUID, accepted: Bool) async throws -> Trade {
        struct B: Encodable { let accepted: Bool }
        return try await post("v1/trades/\(id.uuidString.lowercased())/accept", B(accepted: accepted))
    }

    func deleteTrade(id: UUID) async throws {
        try await delete("v1/trades/\(id.uuidString.lowercased())")
    }

    func closeWeek() async throws -> WeekCloseResponse {
        try await post("v1/week/close")
    }
}
