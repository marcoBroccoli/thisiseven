#if os(iOS)
    import SwiftUI
    import UIKit

    /// Loads authenticated avatar bytes for a member id (nil = no network fetch).
    public typealias EvenAvatarLoader = @Sendable (UUID) async -> Data?

    private struct EvenAvatarLoaderKey: EnvironmentKey {
        static let defaultValue: EvenAvatarLoader? = nil
    }

    public extension EnvironmentValues {
        var evenAvatarLoader: EvenAvatarLoader? {
            get { self[EvenAvatarLoaderKey.self] }
            set { self[EvenAvatarLoaderKey.self] = newValue }
        }
    }

    /// Circular member marker — photo + accent ring when available, else initial fill.
    public struct EvenMemberAvatar: View {
        public var memberId: UUID
        public var displayName: String
        public var accent: Color
        public var hasAvatar: Bool
        public var size: CGFloat
        public var ringWidth: CGFloat
        /// Optimistic local bytes (e.g. right after PhotosPicker, before upload).
        public var localPhoto: Data?

        @Environment(\.evenAvatarLoader) private var loader
        @State private var remotePhoto: Data?

        public init(
            memberId: UUID,
            displayName: String,
            accent: Color,
            hasAvatar: Bool,
            size: CGFloat,
            ringWidth: CGFloat = 2,
            localPhoto: Data? = nil
        ) {
            self.memberId = memberId
            self.displayName = displayName
            self.accent = accent
            self.hasAvatar = hasAvatar
            self.size = size
            self.ringWidth = ringWidth
            self.localPhoto = localPhoto
        }

        public var body: some View {
            ZStack {
                if let uiImage = resolvedImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Text(initial)
                        .font(.system(size: size * 0.38, weight: .semibold, design: .serif))
                        .foregroundStyle(EvenTokens.paperCard)
                        .frame(width: size, height: size)
                        .background(accent, in: Circle())
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(accent, lineWidth: ringWidth)
            )
            .frame(width: size, height: size)
            .accessibilityLabel(displayName)
            .task(id: avatarTaskID) {
                await loadRemote()
            }
        }

        private var avatarTaskID: String {
            "\(memberId.uuidString)-\(hasAvatar)-\(localPhoto?.count ?? 0)"
        }

        private var resolvedImage: UIImage? {
            if let localPhoto, let img = UIImage(data: localPhoto) { return img }
            if let remotePhoto, let img = UIImage(data: remotePhoto) { return img }
            return nil
        }

        private var initial: String {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let first = trimmed.first else { return "?" }
            return String(first).uppercased()
        }

        private func loadRemote() async {
            guard hasAvatar, localPhoto == nil else {
                remotePhoto = nil
                return
            }
            guard let loader else { return }
            remotePhoto = await loader(memberId)
        }
    }

    #Preview("EvenMemberAvatar") {
        HStack(spacing: 16) {
            EvenMemberAvatar(
                memberId: UUID(),
                displayName: "Ada",
                accent: EvenTokens.terracotta,
                hasAvatar: false,
                size: 56
            )
            EvenMemberAvatar(
                memberId: UUID(),
                displayName: "Umut",
                accent: EvenTokens.pine,
                hasAvatar: false,
                size: 28,
                ringWidth: 1.5
            )
        }
        .padding()
        .background(EvenTokens.paperGround)
    }
#endif
