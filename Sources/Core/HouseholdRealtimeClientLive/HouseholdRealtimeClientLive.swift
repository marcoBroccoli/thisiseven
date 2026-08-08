import Dependencies
import EvenCore
import Foundation
import HouseholdRealtimeClient

extension HouseholdRealtimeClient: DependencyKey {
    public static let liveValue: HouseholdRealtimeClient = .live()

    public static func live(
        environment: APIEnvironment = .current,
        session: URLSession = .shared
    ) -> HouseholdRealtimeClient {
        HouseholdRealtimeClient(
            events: {
                AsyncStream { continuation in
                    let bridge = HouseholdRealtimeSession(
                        environment: environment,
                        session: session,
                        continuation: continuation
                    )
                    continuation.onTermination = { _ in
                        Task { await bridge.stop() }
                    }
                    Task { await bridge.start() }
                }
            }
        )
    }
}

// MARK: - Session

private actor HouseholdRealtimeSession {
    private let environment: APIEnvironment
    private let session: URLSession
    private let continuation: AsyncStream<HouseholdRealtimeEvent>.Continuation
    private var task: URLSessionWebSocketTask?
    private var runTask: Task<Void, Never>?
    private var stopped = false

    init(
        environment: APIEnvironment,
        session: URLSession,
        continuation: AsyncStream<HouseholdRealtimeEvent>.Continuation
    ) {
        self.environment = environment
        self.session = session
        self.continuation = continuation
    }

    func start() {
        guard runTask == nil, !stopped else { return }
        runTask = Task { await self.runLoop() }
    }

    func stop() {
        stopped = true
        runTask?.cancel()
        runTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        continuation.finish()
    }

    private func runLoop() async {
        var delay: TimeInterval = 0.5
        while !Task.isCancelled, !stopped {
            do {
                try await connectAndRead()
                delay = 0.5
            } catch is CancellationError {
                break
            } catch {
                if stopped || Task.isCancelled { break }
                try? await Task.sleep(for: .seconds(delay))
                delay = min(delay * 2, 30)
            }
        }
        continuation.finish()
    }

    private func connectAndRead() async throws {
        let store = await MainActor.run { SharedSession.store }
        guard let token = try await store.validAccessToken() else {
            throw APIError.notSignedIn
        }

        var components = URLComponents(
            url: environment.baseURL.appendingPathComponent("v1/ws/household"),
            resolvingAgainstBaseURL: false
        )!
        if components.scheme == "http" {
            components.scheme = "ws"
        } else if components.scheme == "https" {
            components.scheme = "wss"
        }
        // An upgrade cannot carry `X-Household-Id`, so the active household
        // rides the query string instead (`docs/product/API.md`). Unset → the
        // server picks the most recently joined one, as before.
        if let householdID = ActiveHousehold.id {
            components.queryItems = [URLQueryItem(name: "household_id", value: householdID)]
        }

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let ws = session.webSocketTask(with: request)
        task = ws
        ws.resume()

        defer {
            if task === ws {
                task = nil
            }
            ws.cancel(with: .goingAway, reason: nil)
        }

        while !Task.isCancelled, !stopped {
            let message = try await ws.receive()
            switch message {
            case let .string(text):
                if let event = Self.decode(text) {
                    continuation.yield(event)
                }
            case .data:
                break
            @unknown default:
                break
            }
        }
    }

    private nonisolated static func decode(_ text: String) -> HouseholdRealtimeEvent? {
        struct Envelope: Decodable {
            var type: String
            var scopes: [String]?
            var reason: String?
            var actorMemberId: UUID?

            enum CodingKeys: String, CodingKey {
                case type, scopes, reason
                case actorMemberId = "actor_member_id"
            }
        }
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return nil }
        guard envelope.type == "household.invalidate" else { return nil }
        return HouseholdRealtimeEvent(
            type: envelope.type,
            scopes: envelope.scopes ?? [],
            reason: envelope.reason ?? "",
            actorMemberId: envelope.actorMemberId
        )
    }
}
