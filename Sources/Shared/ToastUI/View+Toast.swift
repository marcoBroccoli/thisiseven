import SwiftUI

public extension View {
    /// Installs a **local** top-edge toast host on this view.
    ///
    /// Attach on a screen root. Callers present through `ToastHostCenter` (or a
    /// dependency wrapping it) — delivery lands in this overlay, not a window.
    func toastHost(_ configuration: ToastConfiguration = .standard) -> some View {
        modifier(ToastHostModifier(configuration: configuration))
    }

    /// Presents from an explicit binding (previews / manual triggers).
    func toast(
        _ toast: Binding<Toast?>,
        configuration: ToastConfiguration = .standard,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ToastBindingModifier(
                toast: toast,
                configuration: configuration,
                onDismiss: onDismiss
            )
        )
    }

    /// Convenience for a simple message binding.
    func toast(
        isPresented: Binding<Bool>,
        message: String,
        tone: Toast.Tone = .neutral,
        duration: Duration? = nil,
        configuration: ToastConfiguration = .standard,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        let binding = Binding<Toast?>(
            get: {
                isPresented.wrappedValue
                    ? Toast(message: message, tone: tone, duration: duration)
                    : nil
            },
            set: { newValue in
                isPresented.wrappedValue = newValue != nil
            }
        )
        return toast(binding, configuration: configuration, onDismiss: onDismiss)
    }
}

// MARK: - Host (ToastHostCenter → local overlay)

private struct ToastHostModifier: ViewModifier {
    let configuration: ToastConfiguration

    @StateObject private var host = ToastHostController()

    func body(content: Content) -> some View {
        content
            .toast($host.toast, configuration: configuration)
            .onDisappear {
                host.deactivate()
            }
    }
}

@MainActor
private final class ToastHostController: ObservableObject {
    @Published var toast: Toast?

    private let id = UUID()

    init() {
        // Register in init so early callers can't race past `onAppear`.
        ToastHostCenter.register(
            id: id,
            present: { [weak self] toast in
                self?.toast = toast
            },
            dismiss: { [weak self] in
                self?.toast = nil
            }
        )
    }

    func deactivate() {
        ToastHostCenter.unregister(id: id)
    }
}

// MARK: - Binding-driven overlay

private struct ToastBindingModifier: ViewModifier {
    @Binding var toast: Toast?
    let configuration: ToastConfiguration
    var onDismiss: (() -> Void)?

    @State private var current: Toast?
    @State private var progress: CGFloat = 0
    @State private var dismissTask: Task<Void, Never>?

    private var motion: ToastMotion {
        configuration.motion
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let current {
                    IslandMorphToast(toast: current, progress: progress)
                        .environment(\.toastConfiguration, configuration)
                        .zIndex(1000)
                }
            }
            .onChange(of: toast?.id) { _, _ in
                // Any change after mount is a real present/dismiss and animates.
                // Only a toast that is already set when the host appears is
                // allowed to skip the morph.
                sync(animated: true)
            }
            .onAppear {
                sync(animated: false)
            }
            .onDisappear {
                dismissTask?.cancel()
            }
    }

    private func sync(animated: Bool) {
        dismissTask?.cancel()

        guard let toast else {
            retract(animated: animated)
            return
        }

        current = toast
        progress = 0

        if animated {
            // The overlay is being inserted this pass. Springing to 1 in the
            // same tick gives the animation no start value, so it mounts fully
            // settled — let it render once inside the Island first.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(16))
                guard self.toast?.id == toast.id else { return }
                withAnimation(motion.emerge) { progress = 1 }
            }
        } else {
            progress = 1
        }
        scheduleAutoDismiss(for: toast)
    }

    private func retract(animated: Bool) {
        guard animated else {
            progress = 0
            current = nil
            return
        }
        withAnimation(motion.retract) { progress = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: motion.retractSettle)
            if toast == nil { current = nil }
        }
    }

    private func scheduleAutoDismiss(for toast: Toast) {
        let resolved = toast.duration ?? motion.defaultDuration
        guard resolved > .zero else { return }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: resolved)
            guard !Task.isCancelled else { return }

            withAnimation(motion.retract) { progress = 0 }
            try? await Task.sleep(for: motion.retractSettle)
            guard !Task.isCancelled else { return }

            if self.toast?.id == toast.id {
                self.toast = nil
            }
            current = nil
            onDismiss?()
        }
    }
}

#Preview("Toast · host") {
    ToastHostPreview()
}

private struct ToastHostPreview: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("Success") {
                ToastHostCenter.present(.init(message: "On the calendar", tone: .success))
            }
            Button("Error") {
                ToastHostCenter.present(.init(message: "Couldn’t reach the server", tone: .error))
            }
            Button("Neutral") {
                ToastHostCenter.present(.init(message: "Skipped for now"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.93))
        .toastHost()
    }
}
