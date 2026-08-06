import Foundation

/// Shared `Task.sleep` wrappers for SwiftUI preview / canvas client stubs.
/// Features override endpoints with these so loading spinners and failure
/// paths are visible without inventing ad-hoc sleeps.
public enum PreviewDelay {
    /// Sleep, then complete (no return value).
    public static func delayed(
        _ lag: Duration
    ) -> @Sendable () async throws -> Void {
        {
            try await Task.sleep(for: lag)
        }
    }

    /// Sleep, then return `value()`.
    public static func delayed<Value: Sendable>(
        _ lag: Duration,
        _ value: @escaping @Sendable () -> Value
    ) -> @Sendable () async throws -> Value {
        {
            try await Task.sleep(for: lag)
            return value()
        }
    }

    /// Sleep, then throw.
    public static func delayedThrow<Value: Sendable>(
        _ lag: Duration,
        _ error: some Error
    ) -> @Sendable () async throws -> Value {
        {
            try await Task.sleep(for: lag)
            throw error
        }
    }
}
