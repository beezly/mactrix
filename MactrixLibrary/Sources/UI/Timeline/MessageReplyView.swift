import SwiftUI

public struct MessageReplyView<Content: View>: View {
    let username: String
    let action: () -> Void
    let content: Content

    public init(username: String, message: String, action: @escaping () -> Void = {}) where Content == AnyView {
        self.username = username
        self.action = action
        self.content = AnyView(Text(message.formatAsMarkdown).textSelection(.enabled))
    }

    public init(username: String, action: @escaping () -> Void = {}, @ViewBuilder content: () -> Content) {
        self.username = username
        self.action = action
        self.content = content()
    }

    var label: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(username)
                    .bold()
                    .textSelection(.enabled)
                content
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            ZStack {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 4).opacity(0.5).frame(width: 3)
                    Spacer()
                }
                RoundedRectangle(cornerRadius: 4)
                    .padding(.leading, 2)
                    .opacity(0.05)
            }
        )
        .italic()
    }

    public var body: some View {
        Button {
            action()
        } label: {
            label
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        MessageReplyView(username: "user@example.com", message: "This is the root message")
        Text("Real content")
    }.padding()
}
