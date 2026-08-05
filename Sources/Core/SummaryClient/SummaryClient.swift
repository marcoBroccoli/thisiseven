import Dependencies
import DependenciesMacros
import EvenCore
import Foundation

@DependencyClient
public struct SummaryClient: Sendable {
    public var fetch: @Sendable () async throws -> Summary = {
        throw SummaryClientError.unimplemented
    }
}

public enum SummaryClientError: Error, Sendable {
    case unimplemented
}

extension SummaryClient: TestDependencyKey {
    public static let testValue = SummaryClient()
}

public extension DependencyValues {
    var summaryClient: SummaryClient {
        get { self[SummaryClient.self] }
        set { self[SummaryClient.self] = newValue }
    }
}
