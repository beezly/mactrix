import AppKit
import Models
import SwiftUI
import Testing

@testable import UI

@MainActor
struct MessageEventBodyViewLayoutTests {
    /// Verifies the HStack bottom row renders at zero height when there are no reactions or read receipts,
    /// and expands when content is present — without triggering an infinite layout loop.
    @Test(.timeLimit(.minutes(1)))
    func bottomRowCollapsesWithoutContent() {
        let view = MessageEventBodyView(
            event: MockEventTimelineItem(),
            focused: false,
            reactions: [MockReaction](),
            actions: MockMessageEventActions(),
            ownUserID: "me@example.com",
            imageLoader: nil,
            roomMembers: [MockRoomMember]()
        ) {
            Text("Test message")
        }
        .frame(width: 500)

        let hosting = NSHostingView(rootView: view)
        let emptySize = hosting.fittingSize

        // Now with a reaction
        let viewWithReaction = MessageEventBodyView(
            event: MockEventTimelineItem(),
            focused: false,
            reactions: [MockReaction()],
            actions: MockMessageEventActions(),
            ownUserID: "me@example.com",
            imageLoader: nil,
            roomMembers: [MockRoomMember]()
        ) {
            Text("Test message")
        }
        .frame(width: 500)

        let hostingWithReaction = NSHostingView(rootView: viewWithReaction)
        let reactionSize = hostingWithReaction.fittingSize

        // The view with reactions should be taller than without
        #expect(reactionSize.height > emptySize.height, "Reaction row should add height")
        // Both should have valid non-zero dimensions
        #expect(emptySize.width > 0 && emptySize.height > 0, "Empty state should have valid size")
        #expect(reactionSize.width > 0 && reactionSize.height > 0, "Reaction state should have valid size")
    }

    /// Verifies that rapidly switching between empty and non-empty reactions
    /// completes without hanging (layout loop regression test).
    @Test(.timeLimit(.minutes(1)))
    func rapidReactionToggleDoesNotHang() {
        for _ in 0..<20 {
            let reactions: [MockReaction] = Bool.random() ? [MockReaction()] : []
            let view = MessageEventBodyView(
                event: MockEventTimelineItem(),
                focused: false,
                reactions: reactions,
                actions: MockMessageEventActions(),
                ownUserID: "me@example.com",
                imageLoader: nil,
                roomMembers: [MockRoomMember]()
            ) {
                Text("Test message")
            }
            .frame(width: 500)

            let hosting = NSHostingView(rootView: view)
            let size = hosting.fittingSize
            #expect(size.width > 0 && size.height > 0)
        }
    }
}
