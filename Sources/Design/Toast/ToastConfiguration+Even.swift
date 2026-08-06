import SwiftUI
import ToastUI

/// Even's skin for the portable `ToastUI` module.
///
/// `ToastUI` knows nothing about Even — this is the only place the two meet, so
/// lifting the module into a shared package is a folder move plus this file.
public extension ToastConfiguration {
    static let even = ToastConfiguration(
        style: ToastStyle(
            // Black, not espresso — the pill has to be indistinguishable from
            // the Dynamic Island cutout it grows out of.
            ink: .black,
            label: EvenTokens.paperCard,
            font: .system(size: 14, weight: .semibold, design: .serif),
            neutralAccent: EvenTokens.taupe,
            successAccent: EvenTokens.pine,
            errorAccent: EvenTokens.terracotta
        ),
        motion: ToastMotion(
            emerge: EvenMotion.toastEmerge,
            retract: EvenMotion.toastRetract
        )
    )
}

public extension View {
    /// Even-styled toast host. Attach on a Feature root; reducers keep calling
    /// `toastClient.show`.
    func evenToastHost() -> some View {
        toastHost(.even)
    }
}

#Preview("EvenToast · host") {
    EvenToastHostPreview()
}

private struct EvenToastHostPreview: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("Success") {
                ToastHostCenter.present(.init(message: "ON THE CALENDAR ✓", tone: .success))
            }
            Button("Error") {
                ToastHostCenter.present(.init(message: "Couldn’t reach Google", tone: .error))
            }
            Button("Neutral") {
                ToastHostCenter.present(.init(message: "Skipped for now"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .evenPaperBackground()
        .evenToastHost()
    }
}
