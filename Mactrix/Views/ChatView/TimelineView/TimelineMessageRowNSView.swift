import AppKit
import MatrixRustSDK
import MessageFormatting
import OSLog
import SwiftUI
import UI

// MARK: - Scroll state (shared per controller)

class TimelineScrollState {
    var suppressHover = false
}

// MARK: - Actions bridge

struct TimelineMessageActions: UI.MessageEventActions {
    let timeline: LiveTimeline?
    let event: MatrixRustSDK.EventTimelineItem
    let windowState: WindowState

    func toggleReaction(key: String) {
        Task {
            guard let innerTimeline = timeline?.timeline else { return }
            do {
                let _ = try await innerTimeline.toggleReaction(itemId: event.eventOrTransactionId, key: key)
            } catch {
                Logger.viewCycle.error("Failed to toggle reaction: \(error)")
            }
        }
    }

    func reply() { timeline?.sendReplyTo = event }

    func replyInThread() { windowState.focusThread(rootEventId: event.eventOrTransactionId.id) }

    func pin() {
        guard case let .eventId(eventId: eventId) = event.eventOrTransactionId else { return }
        Task {
            do { let _ = try await timeline?.timeline?.pinEvent(eventId: eventId) }
            catch { Logger.viewCycle.error("Failed to pin message: \(error)") }
        }
    }

    func focusUser() { windowState.focusUser(userId: event.sender) }
}

// MARK: - Row view

class TimelineMessageRowNSView: NSView {

    // MARK: Layout constants

    private let avatarColumnWidth: CGFloat = 64
    private let horizontalPadding: CGFloat = 10
    private let bodyVerticalPadding: CGFloat = 4

    // MARK: Persistent subviews

    private let mainStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: State

    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    private var profileView: NSView?
    private var bodyRowView: NSView?
    private var reactionsView: NSView?
    private var hoverActionsView: NSView?
    private var backgroundHighlight: NSView?
    private var bodyTextField: NSTextField?  // tracked for preferredMaxLayoutWidth
    private var actions: TimelineMessageActions?
    private var event: MatrixRustSDK.EventTimelineItem?
    private var isFocused = false
    private var mainStackWidth: NSLayoutConstraint?

    /// Shared per-controller state to suppress hover during scrolling.
    var scrollState: TimelineScrollState?

    // MARK: Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        let widthC = mainStack.widthAnchor.constraint(equalToConstant: 0)
        mainStackWidth = widthC
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthC,
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Configure

    /// Adds a SwiftUI view to the mainStack as a full-width NSHostingView.
    private func addHostedView<V: View>(_ view: V) {
        let hostView = NSHostingView(rootView: AnyView(view))
        hostView.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(hostView)
        hostView.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
    }

    func configure(
        rowInfo: TimelineItemRowInfo,
        timeline: LiveTimeline?,
        appState: AppState,
        windowState: WindowState
    ) {
        clearSubviews()

        switch rowInfo {
        case .message(let event, let content):
            configureMessage(event: event, content: content, timeline: timeline, appState: appState, windowState: windowState)
        case .state(let event):
            addHostedView(
                UI.GenericEventView(event: event, name: event.content.description)
                    .frame(maxWidth: .infinity, alignment: .leading)
            )
        case .virtual(let virtual):
            addHostedView(
                UI.VirtualItemView(item: virtual.asModel)
                    .frame(maxWidth: .infinity)
            )
        }
    }

    private func configureMessage(
        event: MatrixRustSDK.EventTimelineItem,
        content: MatrixRustSDK.MsgLikeContent,
        timeline: LiveTimeline?,
        appState: AppState,
        windowState: WindowState
    ) {
        self.event = event
        let actions = TimelineMessageActions(timeline: timeline, event: event, windowState: windowState)
        self.actions = actions
        self.isFocused = timeline?.focusedTimelineEventId == event.eventOrTransactionId

        let imageLoader = appState.matrixClient
        let raw = UserDefaults.standard.integer(forKey: "fontSize")
        let fontSize = CGFloat(raw == 0 ? 13 : max(9, min(raw, 72)))
        let ownUserId = (try? appState.matrixClient?.client.userId()) ?? ""

        // 1. Profile header
        let profile = UI.MessageEventProfileView(event: event, actions: actions, imageLoader: imageLoader)
            .font(.system(size: fontSize))
            .environment(appState).environment(windowState)
        addHostedView(profile)
        profileView = mainStack.arrangedSubviews.last

        // 2. Body row
        let bodyRow = makeBodyRow(event: event, content: content, actions: actions,
                                  timeline: timeline, appState: appState, windowState: windowState, fontSize: fontSize)
        mainStack.addArrangedSubview(bodyRow)
        bodyRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
        bodyRowView = bodyRow

        // 3. Reactions + read receipts
        if !content.reactions.isEmpty || !event.userReadReceipts.isEmpty {
            let reactionsRow = makeReactionsRow(
                event: event, reactions: content.reactions, actions: actions,
                ownUserId: ownUserId, imageLoader: imageLoader, roomMembers: timeline?.room.members ?? []
            )
            mainStack.addArrangedSubview(reactionsRow)
            reactionsRow.translatesAutoresizingMaskIntoConstraints = false
            reactionsRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true
            reactionsView = reactionsRow
        }

        updateHoverState()
    }

    private func clearSubviews() {
        mainStack.arrangedSubviews.forEach { mainStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        hoverActionsView?.removeFromSuperview(); hoverActionsView = nil
        reactionsView = nil
        profileView = nil; bodyRowView = nil; backgroundHighlight = nil; bodyTextField = nil
    }

    // MARK: Body row

    private func makeBodyRow(
        event: MatrixRustSDK.EventTimelineItem,
        content: MatrixRustSDK.MsgLikeContent,
        actions: TimelineMessageActions,
        timeline: LiveTimeline?,
        appState: AppState, windowState: WindowState,
        fontSize: CGFloat
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Background highlight
        let bg = NSView()
        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 4
        container.addSubview(bg)
        backgroundHighlight = bg

        // Timestamp
        let timestamp = NSTextField(labelWithString: Self.formatTimestamp(event.date))
        timestamp.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timestamp.textColor = .secondaryLabelColor
        timestamp.translatesAutoresizingMaskIntoConstraints = false
        timestamp.setContentHuggingPriority(.required, for: .horizontal)
        container.addSubview(timestamp)

        // Content stack
        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentStack)

        /// Adds a view to the content stack, pinning hosting views to full width.
        func addToContentStack(_ view: NSView) {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentStack.addArrangedSubview(view)
            if view is NSHostingView<AnyView> {
                view.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            }
        }

        /// Wraps a SwiftUI view in an NSHostingView and adds it to the content stack, left-aligned and full width.
        func addSwiftUIToContentStack<V: View>(_ view: V) {
            let hostView = NSHostingView(rootView: AnyView(
                view.frame(maxWidth: .infinity, alignment: .leading)
            ))
            addToContentStack(hostView)
        }

        // Reply context
        if let replyTo = content.inReplyTo {
            let eventId = replyTo.eventId()
            let embeddedEvent = timeline?.loadedReplyDetails[eventId]?.event() ?? replyTo.event()
            addSwiftUIToContentStack(
                EmbeddedMessageView(embeddedEvent: embeddedEvent) {
                    timeline?.focusEvent(id: .eventId(eventId: eventId))
                }
                .padding(.bottom, 10).environment(appState).environment(windowState)
            )
        }

        // Message body
        let bodyView = makeBodyContent(content: content, actions: actions, timeline: timeline,
                                       appState: appState, windowState: windowState, fontSize: fontSize)
        addToContentStack(bodyView)

        // Thread summary
        if let threadSummary = content.threadSummary {
            addSwiftUIToContentStack(
                MessageThreadSummary(summary: threadSummary) {
                    windowState.focusThread(rootEventId: event.eventOrTransactionId.id)
                }
            )
        }

        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            bg.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            bg.topAnchor.constraint(equalTo: container.topAnchor),
            bg.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            timestamp.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            timestamp.widthAnchor.constraint(equalToConstant: 54),
            timestamp.topAnchor.constraint(equalTo: contentStack.topAnchor, constant: 3),
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding + avatarColumnWidth),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: bodyVerticalPadding),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -bodyVerticalPadding),
        ])

        return container
    }

    // MARK: Body content

    private func makeBodyContent(
        content: MatrixRustSDK.MsgLikeContent,
        actions: TimelineMessageActions,
        timeline: LiveTimeline?,
        appState: AppState, windowState: WindowState,
        fontSize: CGFloat
    ) -> NSView {
        switch content.kind {
        case .message(let msgContent):
            switch msgContent.msgType {
            case .text(let text):
                return makeTextField(messageContent: text, fontSize: fontSize)
            case .notice(let notice):
                return makeTextField(messageContent: notice, fontSize: fontSize, textColor: .secondaryLabelColor)
            case .emote(let emote):
                return makeTextField(string: "Emote: \(emote.body)", fontSize: fontSize)
            default:
                return makeSwiftUIBody(content: content, timeline: timeline, appState: appState, windowState: windowState, fontSize: fontSize)
            }
        case .redacted:
            return makeTextField(string: "Message redacted", fontSize: fontSize, italic: true, textColor: .secondaryLabelColor)
        case .unableToDecrypt:
            return makeTextField(string: "Unable to decrypt", fontSize: fontSize, italic: true, textColor: .secondaryLabelColor)
        default:
            return makeSwiftUIBody(content: content, timeline: timeline, appState: appState, windowState: windowState, fontSize: fontSize)
        }
    }

    /// Direct NSTextField — the main performance win over SwiftUI wrapping.
    private func makeTextField(messageContent: some MessageContent, fontSize: CGFloat, textColor: NSColor? = nil) -> NSTextField {
        let field: NSTextField
        if let formatted = messageContent.formatted, formatted.format == .html {
            field = NSTextField(labelWithAttributedString: parseFormattedBody(formatted.body, baseFontSize: fontSize))
        } else {
            field = NSTextField(labelWithString: messageContent.body)
            field.font = .systemFont(ofSize: fontSize)
        }
        return configureTextField(field, textColor: textColor)
    }

    private func makeTextField(string: String, fontSize: CGFloat, italic: Bool = false, textColor: NSColor? = nil) -> NSTextField {
        let field = NSTextField(labelWithString: string)
        var font = NSFont.systemFont(ofSize: fontSize)
        if italic {
            let desc = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.italic))
            font = NSFont(descriptor: desc, size: fontSize) ?? font
        }
        field.font = font
        return configureTextField(field, textColor: textColor)
    }

    @discardableResult
    private func configureTextField(_ field: NSTextField, textColor: NSColor?) -> NSTextField {
        if let textColor { field.textColor = textColor }
        field.isEditable = false
        field.isSelectable = true
        field.allowsEditingTextAttributes = true
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        field.lineBreakStrategy = .standard
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultHigh, for: .vertical)
        bodyTextField = field
        return field
    }

    private func makeSwiftUIBody(
        content: MatrixRustSDK.MsgLikeContent,
        timeline: LiveTimeline?,
        appState: AppState, windowState: WindowState,
        fontSize: CGFloat
    ) -> NSView {
        let hostView = NSHostingView(rootView: AnyView(
            ChatMessageSwiftUIBody(content: content, timeline: timeline)
                .font(.system(size: fontSize))
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(appState).environment(windowState)
        ))
        hostView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        hostView.setContentCompressionResistancePriority(.required, for: .vertical)
        return hostView
    }

    // MARK: Reactions row

    private func makeReactionsRow(
        event: MatrixRustSDK.EventTimelineItem,
        reactions: [MatrixRustSDK.Reaction],
        actions: TimelineMessageActions,
        ownUserId: String,
        imageLoader: ImageLoader?,
        roomMembers: [MatrixRustSDK.RoomMember]
    ) -> NSView {
        let row = HStack {
            Spacer().frame(width: 64)
            ForEach(reactions) { reaction in
                MessageReactionView(
                    reaction: reaction,
                    active: Binding(
                        get: { reaction.senders.contains { $0.senderId == ownUserId } },
                        set: { newValue in
                            if newValue != reaction.senders.contains(where: { $0.senderId == ownUserId }) {
                                actions.toggleReaction(key: reaction.key)
                            }
                        }
                    )
                )
            }
            Spacer()
            if !event.userReadReceipts.isEmpty {
                UI.ReadReciptsView(receipts: event.userReadReceipts, imageLoader: imageLoader, roomMembers: roomMembers)
                    .padding(.horizontal, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)

        let hostView = NSHostingView(rootView: AnyView(row))
        hostView.translatesAutoresizingMaskIntoConstraints = false
        return hostView
    }

    // MARK: Hover

    func activateHover() {
        guard !isHovered else { return }
        isHovered = true
        updateHoverState()
        showHoverActions()
    }

    func dismissHover() {
        guard isHovered else { return }
        isHovered = false
        updateHoverState()
        hideHoverActions()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        guard !(scrollState?.suppressHover ?? false) else { return }
        isHovered = true
        updateHoverState()
        showHoverActions()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateHoverState()
        hideHoverActions()
    }

    private func updateHoverState() {
        backgroundHighlight?.layer?.backgroundColor = (isHovered || isFocused)
            ? (isFocused ? NSColor.controlAccentColor : NSColor.gray).withAlphaComponent(0.1).cgColor
            : nil
    }

    private func showHoverActions() {
        guard hoverActionsView == nil, let actions, let event else { return }
        let hostView = NSHostingView(rootView: AnyView(HoverActionsView(event: event, actions: actions)))
        hostView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostView)
        NSLayoutConstraint.activate([
            hostView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            hostView.topAnchor.constraint(equalTo: bodyRowView?.topAnchor ?? topAnchor, constant: -10),
        ])
        hoverActionsView = hostView
    }

    private func hideHoverActions() {
        hoverActionsView?.removeFromSuperview()
        hoverActionsView = nil
    }

    // MARK: Layout

    override func layout() {
        // Drive mainStack width from table column, not from content
        if mainStackWidth?.constant != bounds.width {
            mainStackWidth?.constant = bounds.width
        }
        super.layout()
        if let bodyTextField {
            let available = bounds.width - avatarColumnWidth - (horizontalPadding * 2)
            if bodyTextField.preferredMaxLayoutWidth != available {
                bodyTextField.preferredMaxLayoutWidth = available
            }
        }
    }

    // MARK: Helpers

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func formatTimestamp(_ date: Date) -> String {
        timestampFormatter.string(from: date)
    }
}

// MARK: - Hover actions (SwiftUI)

private struct HoverActionsView: View {
    let event: MatrixRustSDK.EventTimelineItem
    let actions: TimelineMessageActions

    var body: some View {
        HStack(spacing: 0) {
            UI.HoverButton(icon: { Text("👍") }, tooltip: "React") { actions.toggleReaction(key: "👍") }
            UI.HoverButton(icon: { Text("🎉") }, tooltip: "React") { actions.toggleReaction(key: "🎉") }
            UI.HoverButton(icon: { Text("❤️") }, tooltip: "React") { actions.toggleReaction(key: "❤️") }
            Divider().frame(height: 18)
            UI.HoverButton(icon: { Image(systemName: "face.smiling") }, tooltip: "React") {}
            if event.canBeRepliedTo {
                UI.HoverButton(icon: { Image(systemName: "arrowshape.turn.up.left") }, tooltip: "Reply") { actions.reply() }
                UI.HoverButton(icon: { Image(systemName: "ellipsis.message") }, tooltip: "Reply in thread") { actions.replyInThread() }
            }
            UI.HoverButton(icon: { Image(systemName: "pin") }, tooltip: "Pin") { actions.pin() }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                .shadow(color: .black.opacity(0.1), radius: 4)
        )
    }
}

// MARK: - SwiftUI body fallback for non-text messages

private struct ChatMessageSwiftUIBody: View {
    let content: MatrixRustSDK.MsgLikeContent
    let timeline: LiveTimeline?

    var body: some View {
        switch content.kind {
        case .message(let msgContent):
            switch msgContent.msgType {
            case .image(let content): MessageImageView(content: content)
            case .video(let content): MessageVideoView(content: content)
            case .file(let content): MessageFileView(content: content)
            case .audio(let content): Text("Audio: \(content.caption ?? "no caption") \(content.filename)").textSelection(.enabled)
            case .gallery(let content): Text("Gallery: \(content.body)").textSelection(.enabled)
            case .location(let content): Text("Location: \(content.body) \(content.geoUri)").textSelection(.enabled)
            case .other(let msgtype, let body): Text("Other: \(msgtype) \(body)").textSelection(.enabled)
            default: EmptyView()
            }
        case .sticker(let body, _, _): Text("Sticker: \(body)").textSelection(.enabled)
        case .poll(let question, _, _, _, _, _, _): Text("Poll: \(question)").textSelection(.enabled)
        case .other(let eventType): Text("Custom event: \(eventType.description)").textSelection(.enabled)
        default: EmptyView()
        }
    }
}
