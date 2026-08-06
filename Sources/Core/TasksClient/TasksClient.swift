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

    /// Canvas default — create/toggle return the laundry fixture.
    public static let previewValue = TasksClient(
        create: { _ in PreviewData.laundry },
        toggle: { _ in PreviewData.laundry },
        delete: { _ in }
    )
}

public extension DependencyValues {
    var tasksClient: TasksClient {
        get { self[TasksClient.self] }
        set { self[TasksClient.self] = newValue }
    }
}
