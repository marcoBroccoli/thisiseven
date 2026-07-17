import SwiftUI
import HouseholdCore

// Even iOS shell v1 (handoff 2026-07-17): Today + Inbox over HouseholdCore
// demo data. Design language per docs/design/README.md — cream paper,
// espresso ink, terracotta accent, serif display. Fonts ship later; the
// system serif design stands in for Newsreader.

enum EvenTokens {
    static let paper = Color(red: 0xE9 / 255, green: 0xE1 / 255, blue: 0xD2 / 255)
    static let paperRaised = Color(red: 0xF6 / 255, green: 0xF1 / 255, blue: 0xE6 / 255)
    static let ink = Color(red: 0x26 / 255, green: 0x20 / 255, blue: 0x1A / 255)
    static let terracotta = Color(red: 0xA6 / 255, green: 0x55 / 255, blue: 0x2F / 255)
    static let pine = Color(red: 0x37 / 255, green: 0x75 / 255, blue: 0x6D / 255)
    static let stone = Color(red: 0x8A / 255, green: 0x7D / 255, blue: 0x69 / 255)
}

public struct EvenRootView: View {
    private let seed = EvenDemoSeed.make()

    public init() {}

    public var body: some View {
        TabView {
            NavigationStack {
                TodayScreen(model: TodayReviewModel(drafts: seed.initialDrafts,
                                                    household: seed.household))
            }
            .tabItem { Label("Today", systemImage: "sun.max") }

            NavigationStack {
                InboxScreen(model: InboxPresentationModel(drafts: seed.initialDrafts),
                            household: seed.household)
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
        }
        .tint(EvenTokens.terracotta)
    }
}

// MARK: - Today

struct TodayScreen: View {
    let model: TodayReviewModel

    var body: some View {
        List {
            ForEach(model.sections, id: \.title) { section in
                Section {
                    ForEach(section.drafts) { draft in
                        DraftRow(draft: draft)
                    }
                } header: {
                    Label(section.title, systemImage: section.systemImage)
                        .font(.system(.footnote, design: .serif).weight(.semibold))
                        .foregroundStyle(EvenTokens.terracotta)
                        .textCase(nil)
                }
            }
            if model.sections.isEmpty {
                ContentUnavailableView("All settled",
                                       systemImage: "checkmark.seal",
                                       description: Text("Nothing needs the two of you today."))
            }
        }
        .scrollContentBackground(.hidden)
        .background(EvenTokens.paper.ignoresSafeArea())
        .navigationTitle("Today")
        .evenLargeTitle()
    }
}

// MARK: - Inbox

struct InboxScreen: View {
    @State var model: InboxPresentationModel
    let household: HouseholdContext

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    counter("Pending", model.pendingApprovalCount, EvenTokens.terracotta)
                    counter("Approved", model.approvedCount, EvenTokens.pine)
                    counter("Needs retry", model.retryRequiredCount, EvenTokens.stone)
                }
                .listRowBackground(EvenTokens.paperRaised)
            }
            Section {
                ForEach(model.drafts) { draft in
                    DraftRow(draft: draft)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(EvenTokens.paper.ignoresSafeArea())
        .navigationTitle("Inbox")
        .evenLargeTitle()
    }

    private func counter(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(EvenTokens.stone)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared row

struct DraftRow: View {
    let draft: InboxDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(draft.title)
                .font(.system(.body, design: .serif).weight(.medium))
                .foregroundStyle(EvenTokens.ink)
            HStack(spacing: 8) {
                if let due = draft.dueDate {
                    Label(due.formatted(date: .abbreviated, time: .omitted),
                          systemImage: "calendar")
                }
                if let amount = draft.amount {
                    Label("€\(amount)", systemImage: "eurosign.circle")
                }
                Spacer()
                statusChip
            }
            .font(.caption)
            .foregroundStyle(EvenTokens.stone)
            if let error = draft.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(EvenTokens.terracotta)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(EvenTokens.paperRaised)
    }

    private var statusChip: some View {
        Text(statusLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.14), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusLabel: String {
        switch draft.status {
        case .pendingApproval: return "Pending"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .calendarRetryRequired: return "Retry"
        case .calendarUpdateRequired: return "Update"
        case .changedExternally: return "Changed"
        default: return String(describing: draft.status).capitalized
        }
    }

    private var statusColor: Color {
        switch draft.status {
        case .approved: return EvenTokens.pine
        case .calendarRetryRequired, .changedExternally: return EvenTokens.terracotta
        default: return EvenTokens.stone
        }
    }
}


extension View {
    /// Large-title mode is iOS-only; swift test builds this target for
    /// macOS too, so the modifier hides behind the platform check.
    @ViewBuilder func evenLargeTitle() -> some View {
        #if os(iOS)
        self.toolbarTitleDisplayMode(.large)
        #else
        self
        #endif
    }
}
