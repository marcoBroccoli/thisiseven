import Dependencies
import DependenciesMacros
import EvenCore
import Foundation

@DependencyClient
public struct TasksClient: Sendable {
    public var create: @Sendable (_ body: EvenAPIClient.TaskDraftBody) async throws -> HouseholdTask = { _ in
        throw TasksClientError.unimplemented
    }

    public var toggle: @Sendable (_ id: UUID) async throws -> HouseholdTask = { _ in
        throw TasksClientError.unimplemented
    }

    public var delete: @Sendable (_ id: UUID) async throws -> Void = { _ in
        throw TasksClientError.unimplemented
    }
}

public enum TasksClientError: Error, Sendable {
    case unimplemented
}

extension TasksClient: TestDependencyKey {
    public static let testValue = TasksClient()
}

public extension DependencyValues {
    var tasksClient: TasksClient {
        get { self[TasksClient.self] }
        set { self[TasksClient.self] = newValue }
    }
}
