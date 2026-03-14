import MatrixRustSDK
import SwiftUI

struct MessageGalleryView: View {
    let content: GalleryMessageContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(content.itemtypes.enumerated()), id: \.offset) { _, item in
                switch item {
                case let .image(content: content):
                    MessageImageView(content: content)
                case let .video(content: content):
                    MessageVideoView(content: content)
                case let .file(content: content):
                    MessageFileView(content: content)
                case let .audio(content: content):
                    Text("Audio: \(content.filename)").textSelection(.enabled)
                case let .other(itemtype: itemtype, body: body):
                    Text("\(itemtype): \(body)").textSelection(.enabled)
                }
            }
        }
    }
}
