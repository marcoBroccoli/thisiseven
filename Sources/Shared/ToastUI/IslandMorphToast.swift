import SwiftUI

/// Dynamic-Island morph presentation for `ToastBanner`.
///
/// An Island-sized capsule and a **seed blob** live in one `compositingGroup`,
/// get blurred, then re-thresholded by a shader so they fuse. The seed drops out
/// of the Island (stretching a neck), then expands into the full pill. Reversing
/// `progress` pulls it back in.
///
/// Devices without an Island fall back to a plain top slide.
struct IslandMorphToast: View, Animatable {
    let toast: Toast
    /// 0 = fully inside the Island · 1 = settled banner.
    var progress: CGFloat
    /// Preview escape hatch — render Island geometry regardless of device.
    var forcesIsland: Bool = false

    /// Animate `progress` itself so the body is re-evaluated at every step.
    /// Without this SwiftUI keeps one body (the end state) and lerps each
    /// derived frame/blur/opacity separately — the staged drop, neck and text
    /// timing all collapse into one linear cross-fade, so an animated present
    /// looks nothing like scrubbing progress by hand.
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Tuned to the physical Dynamic Island rather than to any brand, so these
    /// stay fixed while `ToastConfiguration` carries what an app can restyle.
    private enum Metrics {
        /// Slightly under the real Island so goo never bleeds past its edge.
        static let islandSize = CGSize(width: 104, height: 32)
        static let islandTop: CGFloat = 11
        /// Blob shape while still hidden inside the Island — small enough that
        /// what first peeks out is a bead, not a second capsule.
        static let seedSize = CGSize(width: 38, height: 24)
        /// Final gap between Island bottom and banner top.
        static let gap: CGFloat = 30
        static let blurRadius: CGFloat = 20
        /// Blur ceiling as a fraction of the blob's height. Past roughly half,
        /// the blur pushes the blob's peak alpha under the shader threshold and
        /// it dissolves into a smear instead of reading as a solid shape.
        static let blurToHeight: CGFloat = 0.6
        /// Drop runs long so the blob stays close enough to keep a goo neck.
        static let dropEnd: CGFloat = 0.85
        /// Widening starts only after the seed has necked off.
        static let expandStart: CGFloat = 0.45
        /// Amplifies the spring's (small) overshoot into a readable single dip.
        static let bounce: CGFloat = 1.8
        /// Text holds until the pill is nearly full width, then fades up.
        static let contentStart: CGFloat = 0.8
        /// Defocus the message resolves through as it fades in.
        static let contentBlur: CGFloat = 6
    }

    @Environment(\.toastConfiguration) private var configuration

    @State private var hasIsland = false
    @State private var bannerSize = CGSize(width: 220, height: 48)

    private var ink: Color {
        configuration.style.ink
    }

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    measuringBanner
                    if hasIsland || forcesIsland {
                        morphBody
                    } else {
                        slideBody
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .ignoresSafeArea()
            }
            .allowsHitTesting(false)
            .onAppear {
                hasIsland = ScreenMetrics.hasDynamicIsland
            }
    }

    /// Invisible copy that reports the pill's natural size to drive the blob.
    private var measuringBanner: some View {
        ToastLabel(toast: toast)
            .fixedSize()
            .hidden()
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { size in
                guard size.width > 0, size.height > 0 else { return }
                bannerSize = size
            }
    }

    // MARK: - Island morph

    private var morphBody: some View {
        ZStack(alignment: .top) {
            gooLayer
            contentLayer
        }
        // `progress` is already being interpolated frame by frame by Animatable,
        // so every derived frame/padding/blur below is a finished value. Leaving
        // the ambient animation in place makes SwiftUI spring each of them
        // toward a target that is itself still springing, and the compounding
        // reads as the pill bouncing several times.
        .transaction { $0.animation = nil }
        // Pin the whole morph to a stage just big enough for the Island, the
        // settled pill and the blur margin. Letting it span the screen makes
        // the shader rasterize a far larger texture every frame.
        .frame(width: stageSize.width, height: stageSize.height, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Island capsule + seed blob fused by blur and alpha threshold.
    private var gooLayer: some View {
        ZStack(alignment: .top) {
            Capsule(style: .continuous)
                .fill(ink)
                .frame(width: Metrics.islandSize.width, height: Metrics.islandSize.height)
                .padding(.top, Metrics.islandTop)

            Capsule(style: .continuous)
                .fill(ink)
                .frame(width: blobSize.width, height: blobSize.height)
                .padding(.top, blobTop)
        }
        .frame(width: stageSize.width, height: stageSize.height, alignment: .top)
        .compositingGroup()
        .blur(radius: gooBlur)
        .visualEffect { [progress, ink] content, _ in
            content.layerEffect(
                ShaderLibrary.bundle(.module).toastAlphaThreshold(.color(ink)),
                // The shader reads only its own pixel, so it needs no
                // neighbourhood. A non-zero offset inflates the rasterized
                // layer and the effect gets drawn at reduced resolution.
                maxSampleOffset: .zero,
                isEnabled: progress < 0.999
            )
        }
        // Keeps blur bleed from spilling above the physical Island.
        .mask(alignment: .top) {
            Rectangle()
                .padding(.top, Metrics.islandTop + 4)
        }
        // Lifts off the background only once the shape has firmed up.
        .shadow(
            color: configuration.style.shadowColor.opacity(Double(gooTightness)),
            radius: configuration.style.shadowRadius,
            y: configuration.style.shadowOffsetY
        )
    }

    /// Message + accent sit *on* the blob — the blob is the pill, so this layer
    /// carries no background of its own. Clipping to the blob makes the text
    /// wipe in from the Island rather than reflow as the shape widens.
    private var contentLayer: some View {
        ToastLabel(toast: toast)
            .fixedSize()
            .frame(width: blobSize.width, height: blobSize.height)
            .blur(radius: Metrics.contentBlur * (1 - contentReveal))
            .clipShape(Capsule(style: .continuous))
            .padding(.top, blobTop)
            .opacity(Double(contentReveal))
    }

    // MARK: - Curves

    /// Seed leaves the Island — done well before the pill finishes expanding.
    private var drop: CGFloat {
        smoothstep(clamp(progress / Metrics.dropEnd))
    }

    /// Blob grows from seed to full pill.
    private var expand: CGFloat {
        smoothstep(clamp((progress - Metrics.expandStart) / (1 - Metrics.expandStart)))
    }

    /// Blur falls off linearly with progress. Holding it high through the middle
    /// keeps peak alpha under the shader threshold, which renders the neck as a
    /// faint smear instead of a solid fused shape.
    private var gooTightness: CGFloat {
        clamp(progress)
    }

    /// Capped against the blob's own height so a small seed still survives it.
    private var gooBlur: CGFloat {
        let ceiling = blobSize.height * Metrics.blurToHeight
        return min(Metrics.blurRadius, ceiling) * (1 - gooTightness)
    }

    private var blobSize: CGSize {
        CGSize(
            width: lerp(Metrics.seedSize.width, bannerSize.width, expand),
            height: lerp(Metrics.seedSize.height, bannerSize.height, expand)
        )
    }

    /// Smallest canvas that still holds the Island, the settled pill and the
    /// blur bleed around them — this is what the shader has to rasterize.
    private var stageSize: CGSize {
        let margin = Metrics.blurRadius * 2
        return CGSize(
            width: max(bannerSize.width, Metrics.islandSize.width) + margin,
            height: Metrics.islandTop + Metrics.islandSize.height + Metrics.gap
                + bannerSize.height + margin
        )
    }

    /// Blob centre: starts inside the Island, ends at the settled banner.
    private var centerY: CGFloat {
        lerp(seedCenterY, restCenterY, drop) + bounceOffset
    }

    private var seedCenterY: CGFloat {
        Metrics.islandTop + (Metrics.islandSize.height / 2)
    }

    private var restCenterY: CGFloat {
        Metrics.islandTop + Metrics.islandSize.height + Metrics.gap
            + (bannerSize.height / 2)
    }

    /// Every shape curve clamps at 1, so the spring's overshoot is invisible and
    /// the pill lands dead. Reintroduce it as a small vertical spill, faded in
    /// over the tail so it stays out of the drop itself and nothing jumps.
    private var bounceOffset: CGFloat {
        let tail = smoothstep(clamp((progress - Metrics.dropEnd) / (1 - Metrics.dropEnd)))
        return (restCenterY - seedCenterY) * Metrics.bounce * (progress - 1) * tail
    }

    private var blobTop: CGFloat {
        centerY - (blobSize.height / 2)
    }

    /// Message fade + defocus, both driven off the tail of the morph.
    private var contentReveal: CGFloat {
        smoothstep(clamp((progress - Metrics.contentStart) / (1 - Metrics.contentStart)))
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func smoothstep(_ t: CGFloat) -> CGFloat {
        t * t * (3 - 2 * t)
    }

    private func lerp(_ from: CGFloat, _ to: CGFloat, _ t: CGFloat) -> CGFloat {
        from + ((to - from) * t)
    }

    // MARK: - Non-Island fallback

    private var slideBody: some View {
        ToastBanner(toast: toast)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .top)
            .offset(y: -160 * (1 - progress))
            .opacity(progress > 0.05 ? 1 : 0)
    }
}

#Preview("Island morph · animated") {
    IslandMorphPreview()
}

private struct IslandMorphPreview: View {
    @State private var progress: CGFloat = 1

    var body: some View {
        VStack {
            Spacer()
            Button("Drop out") {
                progress = 0
                // Same tick would animate from the current value, not from 0.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(16))
                    withAnimation(ToastMotion.standard.emerge) { progress = 1 }
                }
            }
            Button("Pull back") {
                withAnimation(ToastMotion.standard.retract) { progress = 0 }
            }
            // Past 1 so the spring's bounce overshoot can be scrubbed too.
            Slider(value: $progress, in: 0 ... 1.15)
                .padding(.horizontal, 40)
            Text(String(format: "progress %.2f", progress))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.93))
        .overlay(alignment: .top) {
            IslandMorphToast(
                toast: .init(message: "Couldn’t reach the server", tone: .error),
                progress: progress,
                forcesIsland: true
            )
        }
    }
}
