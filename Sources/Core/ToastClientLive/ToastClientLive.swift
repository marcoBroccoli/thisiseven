import Dependencies
import Foundation
import ToastClient

extension ToastClient: DependencyKey {
    /// Live delivers into the nearest `.toastHost()` on the feature tree.
    public static let liveValue: ToastClient = .hosted()
}
