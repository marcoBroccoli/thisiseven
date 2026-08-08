#if os(iOS)
    import ComposableArchitecture
    import Design
    import SwiftUI

    struct ConnectionsWhyView: View {
        let partnerConnected: Bool

        var body: some View {
            ConnectionsSetupChrome.stepScreen {
                ConnectionsSetupChrome.heroBlock(
                    eyebrow: "OPTIONAL · YOU CAN DO THIS ANY TIME",
                    title: "Let Gmail do\nthe noticing.",
                    subtitle: "Read-only, and yours alone. Even never sends, moves, or deletes mail."
                )

                VStack(alignment: .leading, spacing: 18) {
                    ConnectionsBenefitRow(
                        systemImage: "magnifyingglass",
                        title: "It scans for bills and appointments",
                        bodyText: "Utility bills, dentist reminders, school emails — spotted so neither of you has to be the one who notices."
                    )
                    ConnectionsBenefitRow(
                        systemImage: "tray",
                        title: "Everything lands in your inbox",
                        bodyText: "Yours to review, and no one else’s to read. You decide what leaves it and becomes a shared todo."
                    )
                    ConnectionsBenefitRow(
                        systemImage: "calendar",
                        title: "Approved drafts hit the calendar",
                        bodyText: "One event, one reminder, on the calendar you both share. Never without your yes."
                    )

                    ConnectionsPartnerNote(partnerConnected: partnerConnected)
                        .padding(.top, 4)
                }
                .padding(.top, 30)
            }
        }
    }

    #Preview("Connections · why") {
        ConnectionsView(store: ConnectionsPreviewSupport.why())
    }

    #Preview("Connections · why · partner already connected") {
        ConnectionsView(store: ConnectionsPreviewSupport.whyPartnerConnected())
    }

    #Preview("Connections · why · checking") {
        ConnectionsView(store: ConnectionsPreviewSupport.whyCheckingStatus())
    }

    #Preview("Connections · why · working") {
        ConnectionsView(store: ConnectionsPreviewSupport.whyWorking())
    }
#endif
