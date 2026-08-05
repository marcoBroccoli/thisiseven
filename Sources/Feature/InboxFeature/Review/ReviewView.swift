import ComposableArchitecture
import Design
import EvenCore
import SwiftUI

@ViewAction(for: ReviewReducer.self)
public struct ReviewView: View {
    @Bindable public var store: StoreOf<ReviewReducer>

    public init(store: StoreOf<ReviewReducer>) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(EvenTokens.espresso.opacity(0.14))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            HStack {
                Text("REVIEW DRAFT — EVERYTHING EDITABLE")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                Spacer()
                Button("✕") { send(.closeTapped) }
                    .foregroundStyle(EvenTokens.stone)
            }
            .padding(.top, 12)

            TextField("Task title", text: $store.title)
                .font(.system(size: 17, design: .serif))
                .padding(.top, 10)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    EvenTokens.espresso.opacity(0.16).frame(height: 1.5)
                }

            HStack(spacing: 8) {
                Text("OWNER")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                if let me = store.me {
                    ownerPill(me)
                }
                if let partner = store.partner {
                    ownerPill(partner)
                }
                Spacer()
                Text(dueAmountLine)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .padding(.top, 12)

            Text("CALENDAR REMINDER")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
                .padding(.top, 12)
            FlowLayout(spacing: 6) {
                ForEach(DraftReminder.allCases, id: \.self) { option in
                    Button {
                        send(.selectReminder(option))
                    } label: {
                        Text(option.label.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(store.reminder == option ? EvenTokens.espresso : EvenTokens.paperCard)
                            .foregroundStyle(store.reminder == option ? EvenTokens.paperCard : EvenTokens.espresso)
                            .overlay(
                                Capsule().stroke(
                                    EvenTokens.espresso.opacity(store.reminder == option ? 0 : 0.16),
                                    lineWidth: 1.5
                                )
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)

            HStack(spacing: 8) {
                Button {
                    send(.dismissTapped)
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 15, design: .serif))
                        .foregroundStyle(EvenTokens.stone)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(EvenTokens.espresso.opacity(0.14), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    send(.approveTapped)
                } label: {
                    Text("Approve → Calendar")
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(EvenTokens.paperRaised)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10).fill(EvenTokens.espresso))
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityIdentifier("draft-approve")
            }
            .padding(.top, 16)

            Text("Approval writes one event with a reminder. Never before.")
                .font(.system(size: 11.5, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.stone)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 20)
        .evenPaperBackground(EvenTokens.paperCard)
        .presentationDetents([.medium, .large])
    }

    private func ownerPill(_ member: Member) -> some View {
        let selected = store.ownerMemberId == member.id
        return Button {
            send(.selectOwner(member.id))
        } label: {
            Text(member.displayName.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(selected ? EvenTokens.espresso : EvenTokens.paperCard)
                .foregroundStyle(selected ? EvenTokens.paperCard : EvenTokens.espresso)
                .overlay(
                    Capsule().stroke(EvenTokens.espresso.opacity(selected ? 0 : 0.16), lineWidth: 1.5)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var dueAmountLine: String {
        var parts: [String] = []
        if let cents = store.draft.amountCents {
            parts.append((Double(cents) / 100).formatted(.currency(code: "EUR")))
        }
        if let due = store.draft.dueOn {
            parts.append("DUE \(due)")
        }
        return parts.joined(separator: " · ")
    }
}

/// Minimal wrapping layout for reminder chips (avoids pulling UIKit FlowLayout deps).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}
