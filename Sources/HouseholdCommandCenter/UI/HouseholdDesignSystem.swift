import SwiftUI

enum AppPalette {
    static let canvas = Color(red: 0.933, green: 0.925, blue: 0.906)
    static let surface = Color.white
    static let cardFill = Color(red: 0.972, green: 0.969, blue: 0.961)
    static let chipFill = Color(red: 0.935, green: 0.931, blue: 0.918)
    static let ink = Color(red: 0.086, green: 0.086, blue: 0.086)
    static let secondaryText = Color(red: 0.278, green: 0.278, blue: 0.267)
    static let muted = Color(red: 0.435, green: 0.431, blue: 0.412)
    static let purple = Color(red: 0.420, green: 0.373, blue: 0.780)
    static let purpleDark = Color(red: 0.290, green: 0.247, blue: 0.569)
    static let purpleSoft = Color(red: 0.949, green: 0.937, blue: 0.988)
    static let teal = Color(red: 0.227, green: 0.541, blue: 0.510)
    static let red = Color(red: 0.702, green: 0.153, blue: 0.122)
    static let redSoft = Color(red: 0.984, green: 0.906, blue: 0.898)
    static let amber = Color(red: 0.890, green: 0.604, blue: 0.122)
    static let amberText = Color(red: 0.604, green: 0.376, blue: 0.031)
    static let amberSoft = Color(red: 0.984, green: 0.937, blue: 0.859)
    static let line = Color(red: 0.831, green: 0.820, blue: 0.796)
}

struct AppSurfaceCard<Content: View>: View {
    var fill: Color = AppPalette.surface
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppPalette.line, lineWidth: 1)
            }
    }
}

struct AppSectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppPalette.ink)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(AppPalette.muted)
        }
    }
}

struct AppSettingsGroup<Content: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var content: Content

    var body: some View {
        AppSurfaceCard(fill: AppPalette.cardFill) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(AppPalette.ink)
                content
                    .foregroundStyle(AppPalette.secondaryText)
            }
        }
    }
}

struct FlowButtonRow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                content()
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
    }
}

struct MobilePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(AppPalette.purple.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MobileSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppPalette.purpleDark.opacity(configuration.isPressed ? 0.72 : 1))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(AppPalette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppPalette.line, lineWidth: 1)
            }
    }
}

struct MobileIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(AppPalette.ink.opacity(0.72))
            .padding(9)
            .background(AppPalette.chipFill.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct TodayCircleButtonStyle: ButtonStyle {
    var foreground: Color
    var background: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(foreground.opacity(configuration.isPressed ? 0.72 : 1))
            .frame(width: 30, height: 30)
            .background(background.opacity(configuration.isPressed ? 0.72 : 1), in: Circle())
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        AppSectionHeader(title: title, subtitle: subtitle)
    }
}

struct SettingsGroup<Content: View>: View {
    var title: String
    var icon: String
    @ViewBuilder var content: Content

    var body: some View {
        AppSettingsGroup(title: title, icon: icon) {
            content
        }
    }
}

extension View {
    @ViewBuilder
    func platformHelp(_ text: String) -> some View {
        #if os(macOS)
        help(text)
        #else
        self
        #endif
    }

    @ViewBuilder
    func mobileSheetSizing() -> some View {
        #if os(macOS)
        frame(minWidth: 360, idealWidth: 420, minHeight: 540)
        #else
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #endif
    }
}
