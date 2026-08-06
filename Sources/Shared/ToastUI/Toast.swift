import Foundation

/// Transient top-edge feedback.
public struct Toast: Equatable, Sendable, Identifiable {
    public enum Tone: Equatable, Sendable {
        case neutral
        case success
        case error
    }

    public let id: UUID
    public var message: String
    public var tone: Tone
    /// Auto-dismiss delay. `nil` → the host's configured default.
    /// `.zero` → stays until dismissed.
    public var duration: Duration?

    public init(
        message: String,
        tone: Tone = .neutral,
        duration: Duration? = nil,
        id: UUID = UUID()
    ) {
        self.id = id
        self.message = message
        self.tone = tone
        self.duration = duration
    }
}
