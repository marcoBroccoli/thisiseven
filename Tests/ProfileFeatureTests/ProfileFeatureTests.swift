import AuthClient
import ComposableArchitecture
import EvenCore
import GoogleClient
import HouseholdClient
import ProfileFeature
import ToastClient
import XCTest

@MainActor
final class ProfileFeatureTests: XCTestCase {
    func testAppearLoadsProfile() async {
        let store = TestStore(initialState: ProfileReducer.State()) {
            ProfileReducer()
        } withDependencies: {
            $0.householdClient.loadProfile = { PreviewData.me }
            $0.householdClient.list = { PreviewData.households }
            $0.googleClient.status = { PreviewData.googleDisconnected }
            $0.toastClient = .silent()
        }
        store.exhaustivity = .off

        await store.send(.view(.appear)) {
            $0.isLoading = true
        }
        await store.receive(\.profileLoaded) {
            $0.isLoading = false
            $0.me = PreviewData.me.member
            $0.partner = PreviewData.household.partner
            $0.householdName = PreviewData.household.name
            $0.inviteCode = PreviewData.household.inviteCode
            $0.draftDisplayName = PreviewData.ada.displayName
        }
    }

    func testCommitDisplayNameSaves() async {
        var state = ProfileReducer.State()
        state.isLoading = false
        state.me = PreviewData.ada
        state.draftDisplayName = "Ada Lovelace"
        state.partner = PreviewData.umut
        state.householdName = PreviewData.household.name

        let updated = Member(
            id: PreviewData.ada.id,
            displayName: "Ada Lovelace",
            color: PreviewData.ada.color,
            isMe: true,
            hasAvatar: PreviewData.ada.hasAvatar
        )

        let store = TestStore(initialState: state) {
            ProfileReducer()
        } withDependencies: {
            $0.householdClient.updateMe = { name, _ in
                XCTAssertEqual(name, "Ada Lovelace")
                return updated
            }
            $0.toastClient = .silent()
        }

        await store.send(.view(.commitDisplayName)) {
            $0.me?.displayName = "Ada Lovelace"
            $0.isSaving = true
        }
        await store.receive(\.saveSucceeded) {
            $0.isSaving = false
            $0.me = updated
            $0.draftDisplayName = "Ada Lovelace"
        }
    }

    func testEmptyDisplayNameValidatesLocally() async {
        var state = ProfileReducer.State()
        state.isLoading = false
        state.me = PreviewData.ada
        state.draftDisplayName = "   "

        let store = TestStore(initialState: state) {
            ProfileReducer()
        }

        await store.send(.view(.commitDisplayName)) {
            $0.nameError = "Name can’t be empty"
        }
    }

    func testSelectColorSavesWithoutSwappingPartner() async {
        var state = ProfileReducer.State()
        state.isLoading = false
        state.me = PreviewData.ada
        state.partner = PreviewData.umut
        state.draftDisplayName = PreviewData.ada.displayName

        let custom = MemberColor(hex: "#4A6FA5")
        let updated = Member(
            id: PreviewData.ada.id,
            displayName: PreviewData.ada.displayName,
            color: custom,
            isMe: true
        )

        let store = TestStore(initialState: state) {
            ProfileReducer()
        } withDependencies: {
            $0.householdClient.updateMe = { _, color in
                XCTAssertEqual(color, custom)
                return updated
            }
            $0.toastClient = .silent()
        }

        await store.send(.view(.selectColor(custom))) {
            $0.me?.color = custom
            $0.isSaving = true
        }
        await store.receive(\.saveSucceeded) {
            $0.isSaving = false
            $0.me = updated
        }
        XCTAssertEqual(store.state.partner?.color, PreviewData.umut.color)
    }

    func testPickAvatarUploads() async {
        var state = ProfileReducer.State()
        state.isLoading = false
        state.me = PreviewData.ada
        state.draftDisplayName = PreviewData.ada.displayName

        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let uploaded = Member(
            id: PreviewData.ada.id,
            displayName: PreviewData.ada.displayName,
            color: PreviewData.ada.color,
            isMe: true,
            hasAvatar: true
        )

        let store = TestStore(initialState: state) {
            ProfileReducer()
        } withDependencies: {
            $0.householdClient.uploadAvatar = { data in
                XCTAssertEqual(data, jpeg)
                return uploaded
            }
            $0.toastClient = .silent()
        }

        await store.send(.view(.pickAvatarJPEG(jpeg))) {
            $0.localAvatarJPEG = jpeg
            $0.me?.hasAvatar = true
            $0.isSaving = true
        }
        await store.receive(\.avatarUploadSucceeded) {
            $0.isSaving = false
            $0.me = uploaded
            $0.localAvatarJPEG = nil
        }
    }

    func testSignOutCallsAuthClient() async {
        let signedOut = LockIsolated(false)
        var state = ProfileReducer.State()
        state.confirmSignOut = true

        let store = TestStore(initialState: state) {
            ProfileReducer()
        } withDependencies: {
            $0.authClient.signOut = {
                signedOut.setValue(true)
            }
        }

        await store.send(.view(.confirmSignOut)) {
            $0.confirmSignOut = false
        }
        // The delegate is the point: AppReducer is one-way, so clearing the
        // session without bubbling `signedOut` strands the app on `.ready`.
        await store.receive(\.delegate.signedOut)
        XCTAssertTrue(signedOut.value)
    }
}
