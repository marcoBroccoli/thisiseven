#if os(iOS)
    import Design
    import EvenCore
    import PhotosUI
    import SwiftUI
    import UIKit

    enum ProfileLayout {
        static let pageHorizontal: CGFloat = 20
        static let sectionGap: CGFloat = 28
        static let cardRadius: CGFloat = 14
        static let avatar: CGFloat = 56
        static let swatch: CGFloat = 32
    }

    /// Quick picks + full ColorPicker — any sRGB is allowed.
    private enum ProfileColorPresets {
        static let swatches: [MemberColor] = [
            .clay,
            .teal,
            MemberColor(hex: "#26201A"), // espresso
            MemberColor(hex: "#8A7D69"), // stone
            MemberColor(hex: "#A0522D"), // terracotta hover
            MemberColor(hex: "#4A6FA5"), // slate blue
            MemberColor(hex: "#8B4D6B"), // plum
            MemberColor(hex: "#C4A35A"), // ochre
        ]
    }

    struct ProfileSectionHeader: View {
        let title: String

        var body: some View {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(EvenTokens.espresso.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    struct ProfileYouCard: View {
        @Binding var displayName: String
        var memberId: UUID
        var color: MemberColor
        var hasAvatar: Bool
        var localAvatarJPEG: Data?
        var nameError: String?
        var isSaving: Bool
        var onCommitName: () -> Void
        var onSelectColor: (MemberColor) -> Void
        var onPickJPEG: (Data) -> Void
        var onRemoveAvatar: () -> Void

        @State private var pickerItem: PhotosPickerItem?
        @State private var showSourceChooser = false
        @State private var showLibrary = false
        @State private var showCamera = false

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    avatarControl

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Your name", text: $displayName)
                            .font(.system(size: 18, weight: .medium, design: .serif))
                            .foregroundStyle(EvenTokens.espresso)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(onCommitName)
                            .disabled(isSaving)
                            .accessibilityIdentifier("Profile display name")

                        if let nameError {
                            Text(nameError)
                                .font(.system(size: 12.5))
                                .foregroundStyle(EvenTokens.terracotta)
                        }

                        if hasAvatar || localAvatarJPEG != nil {
                            Button("Remove photo", action: onRemoveAvatar)
                                .font(.system(size: 13, weight: .medium, design: .serif))
                                .foregroundStyle(EvenTokens.terracotta)
                                .buttonStyle(.evenPlain)
                                .allowsHitTesting(!isSaving)
                                .accessibilityIdentifier("Remove profile photo")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Color")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(EvenTokens.espresso.opacity(0.5))

                    HStack(spacing: 10) {
                        ForEach(ProfileColorPresets.swatches, id: \.hex) { option in
                            Button {
                                onSelectColor(option)
                            } label: {
                                // Flex to the proposed width — nine fixed swatches
                                // outgrow the card on 402pt screens and widen the
                                // whole page.
                                Circle()
                                    .fill(Color(hex: option.rgb))
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                EvenTokens.espresso.opacity(color == option ? 0.9 : 0.12),
                                                lineWidth: color == option ? 2 : 1
                                            )
                                    )
                                    .contentShape(Circle())
                                    .aspectRatio(1, contentMode: .fit)
                                    .frame(maxWidth: ProfileLayout.swatch)
                            }
                            .buttonStyle(.evenPlain)
                            .allowsHitTesting(!isSaving)
                            .accessibilityIdentifier("Profile color \(option.hex)")
                            .accessibilityAddTraits(color == option ? .isSelected : [])
                        }

                        // ColorPicker / UIColorWell is a known XCPreviewAgent
                        // crash source — keep swatches only in canvas.
                        if !ProcessInfo.processInfo.environment.keys.contains("XCODE_RUNNING_FOR_PREVIEWS") {
                            ColorPicker(
                                "",
                                selection: Binding(
                                    get: { Color(hex: color.rgb) },
                                    set: { onSelectColor(MemberColor(uiColor: UIColor($0))) }
                                ),
                                supportsOpacity: false
                            )
                            .labelsHidden()
                            .frame(width: ProfileLayout.swatch, height: ProfileLayout.swatch)
                            .allowsHitTesting(!isSaving)
                            .accessibilityIdentifier("Profile color picker")
                        }
                    }
                }
            }
            .padding(16)
            .profileCardChrome()
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let jpeg = AvatarJPEG.prepare(data)
                    else { return }
                    onPickJPEG(jpeg)
                    pickerItem = nil
                }
            }
        }

        private var avatarControl: some View {
            Button {
                showSourceChooser = true
            } label: {
                EvenMemberAvatar(
                    memberId: memberId,
                    displayName: displayName,
                    accent: Color(hex: color.rgb),
                    hasAvatar: hasAvatar,
                    size: ProfileLayout.avatar,
                    localPhoto: localAvatarJPEG
                )
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EvenTokens.paperCard)
                        .padding(5)
                        .background(EvenTokens.espresso, in: Circle())
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.evenPlain)
            .allowsHitTesting(!isSaving)
            .accessibilityIdentifier("Profile photo")
            .accessibilityLabel("Change profile photo")
            .confirmationDialog("Profile Photo", isPresented: $showSourceChooser, titleVisibility: .visible) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showCamera = true }
                }
                Button("Choose from Library") { showLibrary = true }
                Button("Cancel", role: .cancel) {}
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images, photoLibrary: .shared())
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture(isPresented: $showCamera) { data in
                    if let jpeg = AvatarJPEG.prepare(data) {
                        onPickJPEG(jpeg)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    struct ProfileHouseholdCard: View {
        var householdName: String
        var partner: Member?
        var inviteCode: String
        var onCopyInvite: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                labeled("Household", value: householdName.isEmpty ? "—" : householdName)

                if let partner {
                    HStack(spacing: 10) {
                        EvenMemberAvatar(
                            memberId: partner.id,
                            displayName: partner.displayName,
                            accent: Color(hex: partner.color.rgb),
                            hasAvatar: partner.hasAvatar,
                            size: 28,
                            ringWidth: 1.5
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Partner")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(EvenTokens.espresso.opacity(0.5))
                            Text(partner.displayName)
                                .font(.system(size: 15.5, weight: .medium, design: .serif))
                                .foregroundStyle(EvenTokens.espresso)
                        }
                    }
                } else {
                    Text("No partner yet — share the invite code below.")
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(EvenTokens.espresso.opacity(0.65))
                }

                EvenTokens.espresso.opacity(0.1)
                    .frame(height: 1)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Invite code")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(EvenTokens.espresso.opacity(0.5))
                        Text(inviteCode.isEmpty ? "—" : inviteCode)
                            .font(.system(size: 20, weight: .medium, design: .serif))
                            .foregroundStyle(EvenTokens.espresso)
                            .accessibilityIdentifier("Profile invite code")
                    }
                    Spacer()
                    Button("Copy", action: onCopyInvite)
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            EvenTokens.espresso.opacity(0.08),
                            in: Capsule()
                        )
                        .buttonStyle(.evenPlain)
                        .disabled(inviteCode.isEmpty)
                        .accessibilityIdentifier("Copy invite code")
                }
            }
            .padding(16)
            .profileCardChrome()
        }

        private func labeled(_ title: String, value: String) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(EvenTokens.espresso.opacity(0.5))
                Text(value)
                    .font(.system(size: 17, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
            }
        }
    }

    /// The door to every other place you belong to. A household holds two
    /// people — a person may hold several households.
    struct ProfileHouseholdsLinkRow: View {
        var householdCount: Int
        var pendingInviteCount: Int
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your households")
                            .font(.system(size: 15.5, weight: .medium, design: .serif))
                            .foregroundStyle(EvenTokens.espresso)
                        Text(subtitle)
                            .font(.system(size: 12.5, design: .serif))
                            .italic()
                            .foregroundStyle(EvenTokens.stone)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if pendingInviteCount > 0 {
                        Text("\(pendingInviteCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(EvenTokens.paperCard)
                            .frame(width: 22, height: 22)
                            .background(EvenTokens.terracotta, in: Circle())
                            .accessibilityLabel("\(pendingInviteCount) invites waiting")
                    }

                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EvenTokens.espresso.opacity(0.4))
                }
                .padding(16)
                .contentShape(RoundedRectangle(cornerRadius: ProfileLayout.cardRadius, style: .continuous))
            }
            .buttonStyle(.evenPlain)
            .profileCardChrome()
            .accessibilityIdentifier("Your households")
        }

        private var subtitle: String {
            if pendingInviteCount > 0 {
                return pendingInviteCount == 1
                    ? "One invite is waiting for you"
                    : "\(pendingInviteCount) invites are waiting for you"
            }
            return householdCount <= 1
                ? "Switch places, or start another one"
                : "\(householdCount) places — switch or invite"
        }
    }

    struct ProfileConnectGoogleCard: View {
        var working: Bool
        var onConnect: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Google")
                    .font(.system(size: 15.5, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.espresso)
                Text("Connect Gmail and Calendar to pull household drafts.")
                    .font(.system(size: 13.5, design: .serif))
                    .foregroundStyle(EvenTokens.espresso.opacity(0.65))
                Button(action: onConnect) {
                    Text(working ? "Connecting…" : "Connect Google")
                        .font(.system(size: 14.5, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.espresso)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(EvenTokens.espresso, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.evenPlain)
                .allowsHitTesting(!working)
                .accessibilityIdentifier("Connect Google")
            }
            .padding(16)
            .profileCardChrome()
        }
    }

    struct ProfileSignOutButton: View {
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                Text("Sign out")
                    .font(.system(size: 15.5, weight: .medium, design: .serif))
                    .foregroundStyle(EvenTokens.terracotta)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(EvenTokens.terracotta, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.evenPlain)
            .accessibilityIdentifier("Sign out")
        }
    }

    struct ProfileSkeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: ProfileLayout.sectionGap) {
                RoundedRectangle(cornerRadius: ProfileLayout.cardRadius, style: .continuous)
                    .fill(EvenTokens.espresso.opacity(0.08))
                    .frame(height: 140)
                RoundedRectangle(cornerRadius: ProfileLayout.cardRadius, style: .continuous)
                    .fill(EvenTokens.espresso.opacity(0.08))
                    .frame(height: 160)
                RoundedRectangle(cornerRadius: ProfileLayout.cardRadius, style: .continuous)
                    .fill(EvenTokens.espresso.opacity(0.08))
                    .frame(height: 120)
            }
        }
    }

    private extension View {
        func profileCardChrome() -> some View {
            background(EvenTokens.paperCard)
                .overlay(
                    RoundedRectangle(cornerRadius: ProfileLayout.cardRadius, style: .continuous)
                        .stroke(EvenTokens.espresso.opacity(0.16), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: ProfileLayout.cardRadius, style: .continuous))
        }
    }

    private extension MemberColor {
        init(uiColor: UIColor) {
            var r: CGFloat = 0
            var g: CGFloat = 0
            var b: CGFloat = 0
            var a: CGFloat = 0
            let srgb = CGColorSpace(name: CGColorSpace.sRGB).flatMap {
                uiColor.cgColor.converted(to: $0, intent: .defaultIntent, options: nil)
            }.map(UIColor.init) ?? uiColor
            guard srgb.getRed(&r, green: &g, blue: &b, alpha: &a) else {
                self = .clay
                return
            }
            let rgb =
                (UInt32(min(max(r, 0), 1) * 255) << 16)
                    | (UInt32(min(max(g, 0), 1) * 255) << 8)
                    | UInt32(min(max(b, 0), 1) * 255)
            self.init(hex: String(format: "#%06X", rgb))
        }
    }
#endif
