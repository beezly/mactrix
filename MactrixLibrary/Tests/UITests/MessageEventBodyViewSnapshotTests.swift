import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing

@testable import UI

@MainActor
struct MessageEventBodyViewSnapshotTests {
    @Test func snapshotWithNoReactionsNoReceipts() {
        SnapshotTestHelper.assertViewSnapshot(makeBody(reactions: [], readReceipts: [:]))
    }

    @Test func snapshotWithReactions() {
        SnapshotTestHelper.assertViewSnapshot(makeBody(reactions: [MockReaction()]))
    }

    @Test func snapshotWithReadReceiptsOnly() {
        SnapshotTestHelper.assertViewSnapshot(makeBody(readReceipts: ["user@matrix.org": Receipt(timestamp: .now)]))
    }

    @Test func snapshotWithReactionsAndReadReceipts() {
        SnapshotTestHelper.assertViewSnapshot(
            makeBody(reactions: [MockReaction()], readReceipts: ["user@matrix.org": Receipt(timestamp: .now)])
        )
    }

    private func makeBody(reactions: [MockReaction] = [], readReceipts: [String: Receipt] = [:]) -> some View {
        let event = StableMockEvent(readReceipts: readReceipts)
        return MessageEventBodyView(
            event: event,
            focused: false,
            reactions: reactions,
            actions: MockMessageEventActions(),
            ownUserID: "me@example.com",
            imageLoader: nil,
            roomMembers: [MockRoomMember]()
        ) {
            Text("Hello, world!")
        }
    }
}

/// Mock with a fixed date for stable snapshots.
private struct StableMockEvent: EventTimelineItem {
    var readReceipts: [String: Receipt]
    init(readReceipts: [String: Receipt] = [:]) { self.readReceipts = readReceipts }
    var isRemote: Bool { true }
    var sender: String { "sender@example.com" }
    var senderProfileDetails: ProfileDetails { .ready(displayName: "Sender", displayNameAmbiguous: false, avatarUrl: nil) }
    var isOwn: Bool { false }
    var isEditable: Bool { false }
    var date: Date { Date(timeIntervalSinceReferenceDate: 0) }
    var localCreatedAt: UInt64? { nil }
    var userReadReceipts: [String: Receipt] { readReceipts }
    var canBeRepliedTo: Bool { true }
    var userId: String { sender }
    var displayName: String? { "Sender" }
    var avatarUrl: String? { nil }
}
