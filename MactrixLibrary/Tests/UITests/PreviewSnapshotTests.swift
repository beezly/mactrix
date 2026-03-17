import Models
import SnapshotTesting
import SwiftUI
import Testing

@testable import UI

// MARK: - Timeline Views

@MainActor
struct TimelineSnapshotTests {
    @Test func messageEventBody_noReactions() {
        SnapshotTestHelper.assertViewSnapshot(
            MessageEventBodyView(
                event: MockEventTimelineItem(),
                focused: false,
                reactions: [MockReaction](),
                actions: MockMessageEventActions(),
                ownUserID: "me@example.com",
                imageLoader: nil,
                roomMembers: [MockRoomMember]()
            ) { Text("Hello, world!") }
        )
    }

    @Test func messageEventBody_withReactions() {
        SnapshotTestHelper.assertViewSnapshot(
            MessageEventBodyView(
                event: MockEventTimelineItem(),
                focused: false,
                reactions: [MockReaction()],
                actions: MockMessageEventActions(),
                ownUserID: "me@example.com",
                imageLoader: nil,
                roomMembers: [MockRoomMember()]
            ) { Text("A message with reactions") }
        )
    }

    @Test func messageEventBody_focused() {
        SnapshotTestHelper.assertViewSnapshot(
            MessageEventBodyView(
                event: MockEventTimelineItem(),
                focused: true,
                reactions: [MockReaction](),
                actions: MockMessageEventActions(),
                ownUserID: "me@example.com",
                imageLoader: nil,
                roomMembers: [MockRoomMember]()
            ) { Text("A focused message") }
        )
    }

    @Test func messageEventProfile() {
        SnapshotTestHelper.assertViewSnapshot(
            MessageEventProfileView(
                event: MockEventTimelineItem(),
                actions: MockMessageEventActions(),
                imageLoader: nil
            )
        )
    }

    @Test func messageReaction_inactive() {
        SnapshotTestHelper.assertViewSnapshot(
            MessageReactionView(reaction: MockReaction(), active: .constant(false)),
            width: 200
        )
    }

    @Test func messageReaction_active() {
        SnapshotTestHelper.assertViewSnapshot(
            MessageReactionView(reaction: MockReaction(), active: .constant(true)),
            width: 200
        )
    }

    @Test func messageReply() {
        SnapshotTestHelper.assertViewSnapshot(
            VStack(alignment: .leading, spacing: 10) {
                MessageReplyView(username: "user@example.com", message: "This is the root message")
                MessageReplyView(username: "user@example.com", message: "A longer reply that wraps")
            }.padding()
        )
    }

    @Test func genericEvent() {
        SnapshotTestHelper.assertViewSnapshot(
            VStack(spacing: 0) {
                GenericEventView(event: MockEventTimelineItem(), name: "Test Event")
                GenericEventView(event: MockEventTimelineItem(), name: "Another Event")
            }
        )
    }

    @Test func virtualItems() {
        SnapshotTestHelper.assertViewSnapshot(
            VStack(spacing: 0) {
                VirtualItemView(item: .timelineStart)
                VirtualItemView(item: .dateDivider(date: Date(timeIntervalSinceReferenceDate: 0)))
                VirtualItemView(item: .readMarker)
            }
        )
    }

    @Test func threadTimelineHeader() {
        SnapshotTestHelper.assertViewSnapshot(
            ThreadTimelineHeader {}
        )
    }

    @Test func messageThreadSummary() {
        SnapshotTestHelper.assertViewSnapshot(
            MessageThreadSummary(summary: MockThreadSummary()) {}
                .padding()
        )
    }

    @Test func userTypingIndicator() {
        SnapshotTestHelper.assertViewSnapshot(
            VStack(alignment: .leading) {
                UserTypingIndicator(names: ["John Doe"])
                UserTypingIndicator(names: ["Alice", "Bob"])
            }.padding(),
            width: 400
        )
    }
}

// MARK: - Sidebar Views

@MainActor
struct SidebarSnapshotTests {
    @Test func roomRow_basic() {
        SnapshotTestHelper.assertViewSnapshot(
            List {
                RoomRow(
                    title: "General Chat",
                    avatarUrl: nil,
                    roomInfo: nil,
                    imageLoader: nil,
                    joinRoom: nil
                )
            }.listStyle(.sidebar),
            width: 250,
            height: 80
        )
    }

    @Test func roomRow_withUnread() {
        SnapshotTestHelper.assertViewSnapshot(
            List {
                RoomRow(
                    title: "Unread Room",
                    avatarUrl: nil,
                    roomInfo: MockRoomInfo(),
                    imageLoader: nil,
                    joinRoom: nil
                )
            }.listStyle(.sidebar),
            width: 250,
            height: 80
        )
    }

    @Test func sectionAction() {
        SnapshotTestHelper.assertViewSnapshot(
            List {
                SectionAction(title: "Add Room", systemIcon: "plus.circle", action: {}) {
                    Text("Room 1")
                    Text("Room 2")
                }
            }.listStyle(.sidebar),
            width: 250,
            height: 150
        )
    }
}

// MARK: - Inspector Views

@MainActor
struct InspectorSnapshotTests {
    @Test func userProfileView() {
        SnapshotTestHelper.assertViewSnapshot(
            UserProfileView(
                profile: MockUserProfile(),
                isUserIgnored: false,
                actions: MockUserProfileActions(),
                timelineActions: nil,
                imageLoader: nil
            ),
            width: 250,
            height: 500
        )
    }

    @Test func userProfileRow() {
        SnapshotTestHelper.assertViewSnapshot(
            List {
                UserProfileRow(profile: MockUserProfile(), imageLoader: nil)
            },
            width: 300,
            height: 80
        )
    }

    @Test func eventItemRow() {
        SnapshotTestHelper.assertViewSnapshot(
            List {
                EventItemRow(event: MockEventTimelineItem())
            },
            width: 300,
            height: 80
        )
    }

    @Test func roomInspectorView() {
        SnapshotTestHelper.assertViewSnapshot(
            RoomInspectorView<MockRoom, MockRoomMember>(
                room: MockRoom.previewRoom,
                members: [],
                roomInfo: MockRoomInfo(),
                imageLoader: nil,
                inspectorVisible: .constant(true)
            ),
            width: 250,
            height: 500
        )
    }
}

// MARK: - Room Views

@MainActor
struct RoomSnapshotTests {
    @Test func roomPreviewView() {
        SnapshotTestHelper.assertViewSnapshot(
            RoomPreviewView(
                preview: MockRoomPreviewInfo(),
                imageLoader: nil,
                actions: MockRoomPreviewActions()
            ),
            width: 400,
            height: 600
        )
    }

    @Test func roomEncryptionBadge() {
        SnapshotTestHelper.assertViewSnapshot(
            HStack(spacing: 20) {
                RoomEncryptionBadge(state: .encrypted)
                RoomEncryptionBadge(state: .notEncrypted)
            }.padding(),
            width: 200
        )
    }

    @Test func createRoomScreen() {
        SnapshotTestHelper.assertViewSnapshot(
            CreateRoomScreen { _ in },
            width: 450,
            height: 400
        )
    }
}

// MARK: - Shared Components

@MainActor
struct SharedComponentSnapshotTests {
    @Test func avatarImage() {
        SnapshotTestHelper.assertViewSnapshot(
            AvatarImage(userProfile: MockUserProfile(), imageLoader: nil)
                .frame(width: 64, height: 64),
            width: 80
        )
    }

    @Test func sessionVerificationModal() {
        let data = SessionVerificationData.emojis(
            emojis: [
                MockSessionVerificationEmoji(description: "smiling", symbol: "😄"),
                MockSessionVerificationEmoji(description: "thumbs up", symbol: "👍"),
                MockSessionVerificationEmoji(description: "heart", symbol: "❤️"),
                MockSessionVerificationEmoji(description: "rocket", symbol: "🚀"),
                MockSessionVerificationEmoji(description: "star", symbol: "⭐"),
                MockSessionVerificationEmoji(description: "fire", symbol: "🔥"),
                MockSessionVerificationEmoji(description: "rainbow", symbol: "🌈"),
            ],
            indices: Data()
        )
        SnapshotTestHelper.assertViewSnapshot(
            SessionVerificationModal(verificationData: data) { _ in },
            width: 400,
            height: 350
        )
    }
}
