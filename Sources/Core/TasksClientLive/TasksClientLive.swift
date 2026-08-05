import Dependencies
import EvenCore
import Foundation
import TasksClient

extension TasksClient: DependencyKey {
    public static let liveValue = TasksClient(
        create: { body in
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.createTask(body)
        },
        toggle: { id in
            let api = await MainActor.run { SharedSession.store.api }
            return try await api.toggleTask(id: id)
        },
        delete: { id in
            let api = await MainActor.run { SharedSession.store.api }
            try await api.deleteTask(id: id)
        }
    )
}
