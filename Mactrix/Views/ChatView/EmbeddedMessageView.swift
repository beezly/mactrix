import MatrixRustSDK
import SwiftUI
import UI

struct EmbeddedMessageView: View {
    let embeddedEvent: MatrixRustSDK.EmbeddedEventDetails
    let action: () -> Void

    var body: some View {
        switch embeddedEvent {
        case .unavailable, .pending:
            UI.MessageReplyView(
                username: "loading@username.org",
                message: "Phasellus sit amet purus ac enim semper convallis. Nullam a gravida libero.",
                action: action
            )
            .redacted(reason: .placeholder)
        case let .ready(content, sender, senderProfile, _, _):
            let username = {
                if case let .ready(name, _, _) = senderProfile, let name { return name }
                return sender
            }()
            let msgType: MessageType? = {
                if case .msgLike(let m) = content, case .message(let msg) = m.kind { return msg.msgType }
                return nil
            }()
            switch msgType {
            case .image(let image):
                UI.MessageReplyView(username: username, action: action) {
                    MessageImageView(content: image).frame(maxHeight: 80).allowsHitTesting(false)
                }
            case .video(let video):
                UI.MessageReplyView(username: username, action: action) {
                    MessageVideoView(content: video).frame(maxHeight: 80).allowsHitTesting(false)
                }
            case .file(let file):
                UI.MessageReplyView(username: username, action: action) {
                    MessageFileView(content: file).allowsHitTesting(false)
                }
            default:
                UI.MessageReplyView(username: username, message: content.description, action: action)
            }
        case let .error(message):
            Text("error: \(message)")
        }
    }
}
