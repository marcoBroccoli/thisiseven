import AuthClient
import ComposableArchitecture
import Design
import EvenCore
import SummaryClient
import SwiftUI
import TasksClient
import WidgetClient

@Reducer
public struct TodayFeature {
    @ObservableState
    public struct State: Equatable {
        public var summary: Summary?
        public var me: Member?
        public var partner: Member?
        public var error: String?
        public var isLoading = false
        @Presents public var composer: Composer.State?
        public init() {}
    }

    @Reducer
    public struct Composer {
        @ObservableState
        public struct State: Equatable {
            public var title = ""
            public var weight = 2
            public var ownerIsMe = true
        }

        public enum Action: BindableAction {
            case binding(BindingAction<State>)
            case saveTapped
            case cancelTapped
            case selectWeight(Int)
            case selectOwner(Bool)
        }

        public var body: some ReducerOf<Self> {
            BindingReducer()
            Reduce { state, action in
                switch action {
                case let .selectWeight(w):
                    state.weight = w
                    return .none
                case let .selectOwner(me):
                    state.ownerIsMe = me
                    return .none
                case .binding, .saveTapped, .cancelTapped:
                    return .none
                }
            }
        }
    }

    public enum Action {
        case appear
        case membersLoaded(Member?, Member?)
        case summaryLoaded(Summary)
        case loadFailed(String)
        case toggle(UUID)
        case toggleFailed(String)
        case addTapped
        case composer(PresentationAction<Composer.Action>)
        case createTask
        case createFailed(String)
        case delegate(Delegate)
        public enum Delegate: Equatable {
            case openInbox
        }
    }

    @Dependency(\.summaryClient) var summaryClient
    @Dependency(\.tasksClient) var tasksClient
    @Dependency(\.widgetClient) var widgetClient
    @Dependency(\.authClient) var authClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appear:
                state.isLoading = true
                return .merge(
                    refresh(),
                    .run { [authClient] send in
                        let members = await authClient.householdMembers()
                        await send(.membersLoaded(members.me, members.partner))
                    }
                )

            case let .membersLoaded(me, partner):
                state.me = me
                state.partner = partner
                return .none

            case let .summaryLoaded(summary):
                state.isLoading = false
                state.summary = summary
                return publishWidget(summary)

            case let .loadFailed(message):
                state.isLoading = false
                state.error = message
                return .none

            case let .toggle(id):
                return .run { [tasksClient] send in
                    do {
                        _ = try await tasksClient.toggle(id)
                        await send(.appear)
                    } catch {
                        await send(.toggleFailed(String(describing: error)))
                    }
                }

            case let .toggleFailed(message):
                state.error = message
                return .none

            case .addTapped:
                state.composer = Composer.State()
                return .none

            case .composer(.presented(.saveTapped)):
                return .send(.createTask)

            case .composer(.presented(.cancelTapped)):
                state.composer = nil
                return .none

            case .composer:
                return .none

            case .createTask:
                guard let composer = state.composer else { return .none }
                let owner = composer.ownerIsMe
                    ? (state.me?.id ?? state.summary?.pebbles.first?.memberId)
                    : (state.partner?.id ?? state.summary?.pebbles.dropFirst().first?.memberId)
                guard let owner else { return .none }
                let body = EvenAPIClient.TaskDraftBody(
                    title: composer.title,
                    section: .chore,
                    ownerMemberId: owner,
                    weight: composer.weight,
                    recurrence: .none,
                    dueOn: nil
                )
                state.composer = nil
                return .run { [tasksClient] send in
                    do {
                        _ = try await tasksClient.create(body)
                        await send(.appear)
                    } catch {
                        await send(.createFailed(String(describing: error)))
                    }
                }

            case let .createFailed(message):
                state.error = message
                return .none

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$composer, action: \.composer) {
            Composer()
        }
    }

    private func refresh() -> Effect<Action> {
        .run { [summaryClient] send in
            do {
                try await send(.summaryLoaded(await summaryClient.fetch()))
            } catch {
                await send(.loadFailed(String(describing: error)))
            }
        }
    }

    private func publishWidget(_ summary: Summary) -> Effect<Action> {
        .run { [widgetClient] _ in
            let snap = EvenWidgetSnapshot(
                weekIndex: summary.week.index,
                clay: .init(
                    name: "A", initial: "A", color: .clay,
                    share: summary.percentMe, done: 0
                ),
                teal: .init(
                    name: "B", initial: "B", color: .teal,
                    share: summary.percentPartner, done: 0
                ),
                hasPartner: true,
                leader: summary.caption,
                leftToday: summary.sections.flatMap(\.tasks).filter { !$0.done }.count,
                upcoming: [],
                generatedAt: .now
            )
            await widgetClient.publish(snap)
        }
    }
}

public struct TodayFeatureView: View {
    @Bindable public var store: StoreOf<TodayFeature>

    public init(store: StoreOf<TodayFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.summary == nil {
                    ProgressView().tint(EvenTokens.espresso)
                } else if let summary = store.summary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            if summary.sections.isEmpty {
                                emptyBeam
                            } else {
                                BeamScaleView(
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
            .background(EvenTokens.paperRaised.ignoresSafeArea())
            #if os(iOS)
                .toolbar(.hidden, for: .navigationBar)
            #endif
                .safeAreaInset(edge: .top) {
                    if store.summary != nil {
                        Color.clear.frame(height: 0)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { store.send(.addTapped) } label: {
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
                    ComposerSheet(store: composerStore, me: store.me, partner: store.partner)
                }
        }
        .onAppear { store.send(.appear) }
    }

    private var header: some View {
        HStack(spacing: 7) {
            EvenScaleGlyph()
                .stroke(EvenTokens.espresso, lineWidth: 1.6)
                .frame(width: 15, height: 15)
            Text("Even")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(EvenTokens.espresso)
            Spacer()
        }
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
            store.send(.toggle(task.id))
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

private struct ComposerSheet: View {
    @Bindable var store: StoreOf<TodayFeature.Composer>
    let me: Member?
    let partner: Member?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(EvenTokens.espresso.opacity(0.14))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)

            HStack {
                Text("NEW TODO")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(EvenTokens.stone)
                Spacer()
                Button("✕") { store.send(.cancelTapped) }
                    .foregroundStyle(EvenTokens.stone)
            }
            .padding(.top, 12)

            TextField("What needs doing?", text: $store.title)
                .font(.system(size: 18, design: .serif))
                .padding(.top, 10)
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    EvenTokens.espresso.opacity(0.16).frame(height: 1.5)
                }
                .accessibilityIdentifier("task-title")

            Text("OWNER")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
                .padding(.top, 16)
            HStack(spacing: 8) {
                ownerChip(me?.displayName ?? "Me", selected: store.ownerIsMe) {
                    store.send(.selectOwner(true))
                }
                if partner != nil {
                    ownerChip(partner?.displayName ?? "Partner", selected: !store.ownerIsMe) {
                        store.send(.selectOwner(false))
                    }
                }
            }
            .padding(.top, 6)

            Text("HEFT — HOW MUCH THIS WEIGHS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EvenTokens.stone)
                .padding(.top, 16)
            HStack(spacing: 8) {
                ForEach(1 ... 3, id: \.self) { w in
                    Button {
                        store.send(.selectWeight(w))
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 2.5) {
                                ForEach(0 ..< w, id: \.self) { _ in
                                    Circle().fill(EvenTokens.espresso).frame(width: 6, height: 6)
                                }
                            }
                            .frame(height: 14)
                            Text(w == 1 ? "Light" : w == 2 ? "Medium" : "Heavy")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    store.weight == w ? EvenTokens.espresso : EvenTokens.espresso.opacity(0.16),
                                    lineWidth: 1.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(EvenTokens.espresso)
                }
            }
            .padding(.top, 6)

            EvenPrimaryButton(
                "Add to Today",
                enabled: !store.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                accessibilityId: "task-save"
            ) {
                store.send(.saveTapped)
            }
            .padding(.top, 20)
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 20)
        .background(EvenTokens.paperCard.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func ownerChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(selected ? EvenTokens.espresso : EvenTokens.paperCard)
                .foregroundStyle(selected ? EvenTokens.paperCard : EvenTokens.espresso)
                .overlay(
                    Capsule().stroke(EvenTokens.espresso.opacity(selected ? 0 : 0.16), lineWidth: 1.5)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview("Today · populated") {
    TodayFeatureView(store: TodayPreviewSupport.populated())
}

#Preview("Today · empty") {
    TodayFeatureView(store: TodayPreviewSupport.empty())
}

#Preview("Today · loading") {
    TodayFeatureView(store: TodayPreviewSupport.loading())
}
