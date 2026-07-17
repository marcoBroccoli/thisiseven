import SwiftUI
import EvenCore

// Money — running balance settled weekly, always split 50/50 in MVP.

struct MoneyView: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @State private var adding = false
    @State private var coinSettled = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(kicker: dateLine, title: "Money, settled weekly")

                if let money = model.money {
                    balanceCard(money)
                        .padding(.top, 12)

                    feed(money)

                    if money.feed.isEmpty {
                        VStack(spacing: 8) {
                            Text("No shared receipts yet.")
                                .font(EvenFont.serif(15))
                                .foregroundStyle(palette.ink)
                            Text("Add what one of you fronted — groceries, the internet, the vet.")
                                .font(EvenFont.serif(12.5, italic: true))
                                .foregroundStyle(palette.sub)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 36)
                    }
                } else if model.isLoading {
                    ProgressView().tint(palette.sub).padding(.top, 100)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
        .refreshable { await model.refreshAll() }
        .overlay(alignment: .bottomTrailing) {
            Button {
                adding = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.bg)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(palette.ink).shadow(color: .black.opacity(0.16), radius: 10, y: 5))
            }
            .buttonStyle(PressScaleStyle(scale: 0.9))
            .accessibilityIdentifier("fab-add-expense")
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $adding) {
            AddExpenseSheet(model: model)
        }
        .onChange(of: model.money?.balanceCents) { _, new in
            coinSettled = (new ?? 0) == 0
        }
    }

    private var dateLine: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date()).uppercased()
    }

    // MARK: Balance card

    @ViewBuilder
    private func balanceCard(_ money: Money) -> some View {
        let debtor = model.member(money.debtorMemberId)
        let creditor = model.member(money.creditorMemberId)
        let even = money.balanceCents == 0

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RUNNING BALANCE").capsLabel(9, tracking: 1.5).foregroundStyle(palette.sub)
                Spacer()
                Text("SPLIT 50/50").capsLabel(9, tracking: 1).foregroundStyle(palette.sub)
            }

            Text(EvenFormat.euros(money.balanceCents))
                .font(EvenFont.serif(38, .medium))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .padding(.top, 7)

            Text(owesLine(debtor: debtor, creditor: creditor, even: even))
                .font(EvenFont.serif(13.5, italic: true))
                .foregroundStyle(palette.sub)
                .padding(.top, 5)

            coinRow(debtor: debtor, creditor: creditor, even: even)
                .frame(height: 58)
                .padding(.top, 12)

            settleButton(even: even)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.line, lineWidth: 1))
    }

    private func owesLine(debtor: Member?, creditor: Member?, even: Bool) -> String {
        if even { return "Even on money. The coin made it across." }
        guard let debtor, let creditor else { return "Add shared receipts to see who owes whom." }
        return "\(debtor.displayName) owes \(creditor.displayName) — shared receipts, split evenly."
    }

    @ViewBuilder
    private func coinRow(debtor: Member?, creditor: Member?, even: Bool) -> some View {
        let left = debtor ?? model.me
        let right = creditor ?? model.partner

        ZStack {
            palette.line.frame(width: 220, height: 1.5)

            avatar(left).offset(x: -126)
            avatar(right).offset(x: 126)

            Text("€")
                .font(EvenFont.sans(10, .bold))
                .foregroundStyle(palette.bg)
                .frame(width: 24, height: 24)
                .background(Circle().fill(palette.ink))
                .offset(x: coinSettled ? 86 : -86, y: 0)
                .rotationEffect(.degrees(coinSettled ? 360 : 0))
                .animation(.easeInOut(duration: 0.8), value: coinSettled)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func avatar(_ member: Member?) -> some View {
        let color = member.map { palette.member($0.color) } ?? palette.sub
        Text(member.map { String($0.displayName.prefix(1)).uppercased() } ?? "–")
            .font(EvenFont.sans(12, .bold))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(Circle().fill(color.opacity(0.14)))
            .overlay(Circle().stroke(color, lineWidth: 1.5))
    }

    @ViewBuilder
    private func settleButton(even: Bool) -> some View {
        Button {
            guard !even else { return }
            coinSettled = true
            Task { await model.settle() }
        } label: {
            Text(even ? "Settled ✓" : "Settle up")
                .font(EvenFont.serif(15, .medium))
                .foregroundStyle(even ? palette.sub : palette.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 10).fill(even ? Color.clear : palette.ink))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(even ? palette.line : palette.ink, lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        .disabled(even)
        .accessibilityIdentifier("settle-button")
        .padding(.top, 4)
    }

    // MARK: Feed

    @ViewBuilder
    private func feed(_ money: Money) -> some View {
        VStack(spacing: 0) {
            ForEach(money.feed) { item in
                feedRow(item)
            }
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private func feedRow(_ item: MoneyFeedItem) -> some View {
        let payer = model.member(item.paidByMemberId ?? item.fromMemberId)
        let color = payer.map { palette.member($0.color) } ?? palette.sub

        HStack(spacing: 10) {
            OwnerChip(member: payer, palette: palette)

            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(item))
                    .font(EvenFont.serif(14.5))
                    .foregroundStyle(palette.ink)
                Text(rowMeta(item))
                    .capsLabel(8.5, tracking: 0.5)
                    .foregroundStyle(palette.sub)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(EvenFormat.euros(item.amountCents))
                .font(EvenFont.sans(13, .semibold))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { palette.faint.frame(height: 1) }
        .opacity(item.kind == .expense && (item.settled ?? false) ? 0.5 : 1)
        // Unused variable warning dodge: color is used for chips via payer.
        .accentColor(color)
    }

    private func rowTitle(_ item: MoneyFeedItem) -> String {
        if item.kind == .settlement {
            let from = model.member(item.fromMemberId)?.displayName ?? "Someone"
            let to = model.member(item.toMemberId)?.displayName ?? "someone"
            return "Settle-up — \(from) paid \(to)"
        }
        return item.title ?? "Expense"
    }

    private func rowMeta(_ item: MoneyFeedItem) -> String {
        if item.kind == .settlement { return "CLEARED" }
        var parts: [String] = []
        if let day = item.incurredOn { parts.append(EvenFormat.capsDate(day)) }
        parts.append("SPLIT 50/50")
        if item.settled == true { parts.append("SETTLED") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Add expense

struct AddExpenseSheet: View {
    @Bindable var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amount = ""
    @State private var payerId: UUID?
    @State private var date = Date()
    @State private var saving = false

    var body: some View {
        SheetChrome(title: "SHARED RECEIPT — SPLIT 50/50") {
            UnderlineField(placeholder: "What was it? e.g. Weekly groceries", text: $title, id: "expense-title")

            HStack(spacing: 10) {
                Text("€").font(EvenFont.serif(20)).foregroundStyle(palette.sub)
                UnderlineField(placeholder: "0.00", text: $amount, serifSize: 20, id: "expense-amount")
                    .frame(width: 140)
                Spacer()
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .tint(palette.clay)
            }

            HStack(spacing: 8) {
                Text("PAID BY").capsLabel(9, tracking: 1.4).foregroundStyle(palette.sub)
                ForEach(model.household?.members ?? []) { member in
                    SelectPill(label: member.displayName.uppercased(),
                               selected: payerId == member.id,
                               tint: palette.member(member.color)) {
                        payerId = member.id
                    }
                }
                Spacer()
            }

            PrimaryButton(title: saving ? "Adding…" : "Add receipt",
                          enabled: cents > 0
                                   && !title.trimmingCharacters(in: .whitespaces).isEmpty
                                   && payerId != nil && !saving) {
                guard let payerId else { return }
                saving = true
                Task {
                    let f = DateFormatter()
                    f.dateFormat = "yyyy-MM-dd"
                    let ok = await model.addExpense(.init(
                        title: title.trimmingCharacters(in: .whitespaces),
                        amountCents: cents,
                        paidByMemberId: payerId,
                        incurredOn: f.string(from: date)))
                    saving = false
                    if ok { dismiss() }
                }
            }
            .accessibilityIdentifier("expense-save")
            .padding(.top, 4)
        }
        .onAppear { payerId = model.me?.id }
    }

    private var cents: Int {
        Int(((Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * 100).rounded())
    }
}
