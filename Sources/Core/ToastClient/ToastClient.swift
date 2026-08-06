import Dependencies
import DependenciesMacros
import Foundation
import ToastUI

@DependencyClient
public struct ToastClient: Sendable {
    public var show: @Sendable (Toast) async -> Void = { _ in }
    public var dismiss: @Sendable () async -> Void = {}
}

public extension ToastClient {
    func show(
        _ message: String,
        tone: Toast.Tone = .neutral,
        duration: Duration? = nil
    ) async {
        await show(Toast(message: message, tone: tone, duration: duration))
    }

    /// Delivers into the nearest attached `.toastHost()` (no overlay window).
    static func hosted() -> ToastClient {
        ToastClient(
            show: { toast in
                await MainActor.run {
                    ToastHostCenter.present(toast)
                }
            },
            dismiss: {
                await MainActor.run {
                    ToastHostCenter.dismiss()
                }
            }
        )
    }
}

extension ToastClient: TestDependencyKey {
    public static let testValue = ToastClient()
    /// Previews: same path as Live — needs a host on the feature root.
    public static let previewValue = ToastClient.hosted()
}

public extension DependencyValues {
    var toastClient: ToastClient {
        get { self[ToastClient.self] }
        set { self[ToastClient.self] = newValue }
    }
}
