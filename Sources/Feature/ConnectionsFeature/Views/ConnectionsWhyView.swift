import ComposableArchitecture
import Design
import SwiftUI

struct ConnectionsWhyView: View {
    var body: some View {
        ConnectionsSetupChrome.stepScreen {
            ConnectionsSetupChrome.heroBlock(
                eyebrow: "OPTIONAL · YOU CAN DO THIS ANY TIME",
                title: "Let Gmail do\nthe noticing.",
                subtitle: "Read-only. Even never sends, moves, or deletes mail."
            )

            VStack(alignment: .leading, spacing: 18) {
                ConnectionsBenefitRow(
                    systemImage: "magnifyingglass",
                    title: "It scans for bills and appointments",
                    bodyText: "Utility bills, dentist reminders, school emails — spotted so neither of you has to be the one who notices."
                )
                ConnectionsBenefitRow(
                    systemImage: "tray",
                    title: "Everything lands as a draft",
                    bodyText: "Into the shared Approval Inbox. Your partner approves before anything becomes a task."
                )
                ConnectionsBenefitRow(
                    systemImage: "calendar",
                    title: "Approved drafts hit the calendar",
                    bodyText: "One event, one reminder. Never without a yes from one of you."
                )
            }
            .padding(.top, 30)
        }
    }
}

#Preview("Connections · why") {
    ConnectionsView(store: ConnectionsPreviewSupport.why())
}

#Preview("Connections · why · checking") {
    ConnectionsView(store: ConnectionsPreviewSupport.whyCheckingStatus())
}

#Preview("Connections · why · working") {
    ConnectionsView(store: ConnectionsPreviewSupport.whyWorking())
}
