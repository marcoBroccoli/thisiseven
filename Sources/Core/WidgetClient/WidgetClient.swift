import Dependencies
import DependenciesMacros
import EvenCore
import Foundation

@DependencyClient
public struct WidgetClient: Sendable {
    public var publish: @Sendable (_ snapshot: EvenWidgetSnapshot) async -> Void = { _ in }
}

extension WidgetClient: TestDependencyKey {
    public static let testValue = WidgetClient()

    /// Canvas default — discard publishes.
    public static let previewValue = WidgetClient(
        publish: { _ in }
    )
}

public extension DependencyValues {
    var widgetClient: WidgetClient {
        get { self[WidgetClient.self] }
        set { self[WidgetClient.self] = newValue }
    }
}
