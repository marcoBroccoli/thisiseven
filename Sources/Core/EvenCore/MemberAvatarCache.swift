import Foundation

/// In-memory JPEG cache for household member avatars (keyed by member id).
public actor MemberAvatarCache {
    public static let shared = MemberAvatarCache()

    private var images: [UUID: Data] = [:]

    public func data(for id: UUID) -> Data? {
        images[id]
    }

    public func store(_ id: UUID, data: Data) {
        images[id] = data
    }

    public func remove(_ id: UUID) {
        images[id] = nil
    }

    public func removeAll() {
        images.removeAll()
    }
}
