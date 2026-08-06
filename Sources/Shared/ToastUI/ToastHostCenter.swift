import Foundation

/// Routes programmatic `present` calls into the nearest attached `.toastHost()`.
///
/// Views own presentation by attaching the modifier; callers (reducers, view
/// models) keep a single global-looking call site, with no overlay `UIWindow`.
@MainActor
public enum ToastHostCenter {
    private struct Entry {
        var present: (Toast) -> Void
        var dismiss: () -> Void
    }

    private static var stack: [(id: UUID, entry: Entry)] = []

    public static var hasHost: Bool {
        !stack.isEmpty
    }

    public static func register(
        id: UUID,
        present: @escaping (Toast) -> Void,
        dismiss: @escaping () -> Void
    ) {
        stack.removeAll { $0.id == id }
        stack.append((id, Entry(present: present, dismiss: dismiss)))
    }

    public static func unregister(id: UUID) {
        stack.removeAll { $0.id == id }
    }

    public static func present(_ toast: Toast) {
        stack.last?.entry.present(toast)
    }

    public static func dismiss() {
        stack.last?.entry.dismiss()
    }
}
