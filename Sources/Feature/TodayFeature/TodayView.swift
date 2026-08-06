#if os(iOS)
    import ComposableArchitecture
    import Design
    import EvenCore
    import SwiftUI
    import VisualEffects

    @ViewAction(for: TodayReducer.self)
    public struct TodayView: View {
        @Bindable public var store: StoreOf<TodayReducer>

        public init(store: StoreOf<TodayReducer>) {
            self.store = store
        }

        public var body: some View {
            NavigationStack {
                Group {
                    if store.isLoading && store.summary == nil {
                        TodayLoadingSkeleton()
                    } else if let summary = store.summary {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                header
                                if summary.sections.isEmpty {
                                    emptyBeam
                                } else {
                                    EvenBeamScale(
                                        summary: summary,
                                        me: store.me,
                                        partner: store.partner
                                    )
                                    .frame(height: 240)
                                    .padding(.top, 8)

                                    Text(summary.caption)
                                        .font(.system(size: 14, design: .serif))
                                        .italic()
                                        .foregroundStyle(EvenTokens.stone)
                                        .padding(.top, 8)

                                    ForEach(summary.sections, id: \.key) { section in
                                        Text(section.label)
                                            .font(.system(size: 9.5, weight: .semibold))
                                            .tracking(1.5)
                                            .foregroundStyle(EvenTokens.stone)
                                            .padding(.top, 18)
                                        ForEach(section.tasks) { task in
                                            taskRow(task)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                        }
                    } else {
                        ContentUnavailableView(
                            "Today",
                            systemImage: "sun.max",
                            description: Text(store.error ?? "No summary yet.")
                        )
                    }
                }
                .evenPaperBackground()
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top) {
                    if store.summary != nil {
                        Color.clear.frame(height: 0)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { send(.addTapped) } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(EvenTokens.paperRaised)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(EvenTokens.espresso))
                    }
                    .accessibilityIdentifier("fab-add-task")
                    .padding(.trailing, 20)
                    .padding(.top, 56)
                }
                .sheet(item: $store.scope(state: \.composer, action: \.composer)) { composerStore in
                    ComposerView(store: composerStore, me: store.me, partner: store.partner)
                }
            }
            .onAppear { send(.appear) }
        }

        private var header: some View {
            EvenBrandMark(showsTrailingSpacer: true)
                .padding(.top, 56)
        }

        private var emptyBeam: some View {
            VStack(spacing: 16) {
                Spacer(minLength: 80)
                Capsule().fill(EvenTokens.espresso).frame(width: 150, height: 2)
                Text("Nothing on the beam yet.")
                    .font(.system(size: 19, design: .serif))
                    .italic()
                Text("Add the first chore or errand — tap the + above.")
                    .font(.system(size: 12))
                    .foregroundStyle(EvenTokens.stone)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 80)
            }
            .frame(maxWidth: .infinity)
        }

        private func taskRow(_ task: HouseholdTask) -> some View {
            Button {
                send(.toggle(task.id))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.done ? EvenTokens.espresso : EvenTokens.espresso.opacity(0.35))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.system(size: 15, design: .serif))
                            .strikethrough(task.done)
                            .foregroundStyle(EvenTokens.espresso)
                        Text(task.metaLine)
                            .font(.system(size: 8.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(EvenTokens.stone)
                    }
                    Spacer()
                    HStack(spacing: 2.5) {
                        ForEach(0 ..< task.weight, id: \.self) { _ in
                            Circle().fill(ownerColor(task)).frame(width: 6, height: 6)
                        }
                    }
                    Text(ownerInitial(task))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(EvenTokens.paperCard)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(ownerColor(task)))
                }
                .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("check-\(task.title)")
            .overlay(alignment: .bottom) {
                EvenTokens.espresso.opacity(0.055).frame(height: 1)
            }
        }

        private func ownerColor(_ task: HouseholdTask) -> Color {
            if task.ownerMemberId == store.me?.id { return EvenTokens.terracotta }
            if task.ownerMemberId == store.partner?.id { return EvenTokens.pine }
            return EvenTokens.stone
        }

        private func ownerInitial(_ task: HouseholdTask) -> String {
            if task.ownerMemberId == store.me?.id {
                return String(store.me?.displayName.prefix(1) ?? "A")
            }
            return String(store.partner?.displayName.prefix(1) ?? "U")
        }
    }

    /// Placeholder layout matching Today chrome — redacted until summary arrives.
    struct TodayLoadingSkeleton: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    EvenBrandMark(showsTrailingSpacer: true)
                        .padding(.top, 56)
                        .unredacted()

                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(EvenTokens.espresso.opacity(0.12))
                        .frame(height: 240)
                        .padding(.top, 8)

                    Text("Loading this week’s balance…")
                        .font(.system(size: 14, design: .serif))
                        .italic()
                        .padding(.top, 8)

                    Text("CHORES")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.5)
                        .padding(.top, 18)

                    ForEach(0 ..< 3, id: \.self) { _ in
                        HStack(spacing: 10) {
                            Image(systemName: "circle")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Placeholder chore title")
                                    .font(.system(size: 15, design: .serif))
                                Text("TODAY · WEEKLY")
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .tracking(0.6)
                            }
                            Spacer()
                            Text("A")
                                .font(.system(size: 8.5, weight: .bold))
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(EvenTokens.stone))
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) {
                            EvenTokens.espresso.opacity(0.055).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
                .foregroundStyle(EvenTokens.espresso)
            }
            .evenScrollOnPaper()
            .loading(true)
            .accessibilityLabel("Loading today")
        }
    }

    #Preview("Today · populated") {
        TodayView(store: TodayPreviewSupport.populated())
    }

    #Preview("Today · empty") {
        TodayView(store: TodayPreviewSupport.empty())
    }

    #Preview("Today · loading") {
        TodayView(store: TodayPreviewSupport.loading())
    }
#endif
