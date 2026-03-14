import MatrixRustSDK
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let maxAttachmentSizeDefault: UInt64 = 50 * 1024 * 1024 // 50 MB fallback

struct ChatInputView: View {
    let room: Room
    let timeline: LiveTimeline
    @Binding var replyTo: MatrixRustSDK.EventTimelineItem?
    @AppStorage("fontSize") var fontSize: Int = 13

    @Environment(AppState.self) private var appState

    @State private var isDraftLoaded: Bool = false
    @State private var chatInput: String = ""
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var isSending: Bool = false
    @State private var showFilePicker: Bool = false
    @State private var attachmentError: String?

    private var maxUploadSize: UInt64 {
        get async {
            guard let client = appState.matrixClient?.client else { return maxAttachmentSizeDefault }
            return (try? await client.getMaxMediaUploadSize()) ?? maxAttachmentSizeDefault
        }
    }

    // MARK: - Send

    func sendMessage() async {
        guard let innerTimeline = timeline.timeline else {
            Logger.viewCycle.error("sendMessage: no timeline")
            return
        }

        Logger.viewCycle.info("sendMessage: attachments=\(pendingAttachments.count) text=\(chatInput.isEmpty ? "empty" : "present")")

        if !pendingAttachments.isEmpty {
            isSending = true
            await sendAttachments(timeline: innerTimeline)
            isSending = false
        } else {
            guard !chatInput.isEmpty else { return }
            let msg = messageEventContentFromMarkdown(md: chatInput)
            do {
                if let replyTo {
                    _ = try await innerTimeline.sendReply(msg: msg, eventId: replyTo.eventOrTransactionId.id)
                } else {
                    _ = try await innerTimeline.send(msg: msg)
                }
            } catch {
                Logger.viewCycle.error("failed to send message: \(error)")
            }
        }

        chatInput = ""
        replyTo = nil
        pendingAttachments.removeAll()
        timeline.scrollPosition.scrollTo(edge: .bottom)
    }

    private func sendAttachments(timeline innerTimeline: Timeline) async {
        let caption = chatInput.isEmpty ? nil : chatInput
        let replyToId = replyTo?.eventOrTransactionId.id

        if pendingAttachments.count == 1 {
            await sendSingleAttachment(pendingAttachments[0], caption: caption, replyToId: replyToId, timeline: innerTimeline)
        } else {
            await sendGallery(caption: caption, replyToId: replyToId, timeline: innerTimeline)
        }
    }

    private func sendSingleAttachment(_ attachment: PendingAttachment, caption: String?, replyToId: String?, timeline innerTimeline: Timeline) async {
        do {
            let handle: SendAttachmentJoinHandle
            if attachment.isImage {
                let image = attachment.preview
                // Compute blurhash on a small thumbnail to avoid blocking the UI
                let blurhash: String? = await Task.detached {
                    guard let image else { return nil as String? }
                    let thumbSize = 32
                    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                          let ctx = CGContext(data: nil, width: thumbSize, height: thumbSize,
                                             bitsPerComponent: 8, bytesPerRow: thumbSize * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                    ctx.interpolationQuality = .low
                    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize))
                    guard let smallCG = ctx.makeImage() else { return nil }
                    return NSImage(cgImage: smallCG, size: NSSize(width: thumbSize, height: thumbSize))
                        .blurHash(numberOfComponents: (3, 3))
                }.value
                handle = try innerTimeline.sendImage(
                    params: .init(
                        source: attachment.uploadSource,
                        caption: caption,
                        formattedCaption: nil,
                        mentions: nil,
                        inReplyTo: replyToId
                    ),
                    thumbnailSource: nil,
                    imageInfo: ImageInfo(
                        height: image.map { UInt64($0.size.height) },
                        width: image.map { UInt64($0.size.width) },
                        mimetype: attachment.mimeType,
                        size: UInt64(attachment.data.count),
                        thumbnailInfo: nil, thumbnailSource: nil,
                        blurhash: blurhash, isAnimated: false
                    )
                )
            } else if attachment.isVideo {
                let meta = await attachment.avMetadata()
                let blurhash = await attachment.videoBlurhash()
                handle = try innerTimeline.sendVideo(
                    params: .init(source: attachment.uploadSource, caption: caption, formattedCaption: nil, mentions: nil, inReplyTo: replyToId),
                    thumbnailSource: nil,
                    videoInfo: VideoInfo(duration: meta.duration, height: meta.height, width: meta.width, mimetype: attachment.mimeType, size: UInt64(attachment.data.count), thumbnailInfo: nil, thumbnailSource: nil, blurhash: blurhash)
                )
            } else if attachment.isAudio {
                let meta = await attachment.avMetadata()
                handle = try innerTimeline.sendAudio(
                    params: .init(source: attachment.uploadSource, caption: caption, formattedCaption: nil, mentions: nil, inReplyTo: replyToId),
                    audioInfo: AudioInfo(duration: meta.duration, size: UInt64(attachment.data.count), mimetype: attachment.mimeType)
                )
            } else {
                handle = try innerTimeline.sendFile(
                    params: .init(source: attachment.uploadSource, caption: caption, formattedCaption: nil, mentions: nil, inReplyTo: replyToId),
                    fileInfo: FileInfo(mimetype: attachment.mimeType, size: UInt64(attachment.data.count), thumbnailInfo: nil, thumbnailSource: nil)
                )
            }
            try await handle.join()
        } catch {
            Logger.viewCycle.error("failed to send attachment: \(error)")
            Logger.viewCycle.error("failed to send attachment: \(String(describing: error))")
        }
    }

    private func sendGallery(caption: String?, replyToId: String?, timeline innerTimeline: Timeline) async {
        var itemInfos: [GalleryItemInfo] = []
        for attachment in pendingAttachments {
            if attachment.isImage {
                let image = attachment.preview
                let blurhash: String? = await Task.detached {
                    guard let image else { return nil as String? }
                    let thumbSize = 32
                    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                          let ctx = CGContext(data: nil, width: thumbSize, height: thumbSize,
                                             bitsPerComponent: 8, bytesPerRow: thumbSize * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                    ctx.interpolationQuality = .low
                    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize))
                    guard let smallCG = ctx.makeImage() else { return nil }
                    return NSImage(cgImage: smallCG, size: NSSize(width: thumbSize, height: thumbSize))
                        .blurHash(numberOfComponents: (3, 3))
                }.value
                itemInfos.append(.image(
                    imageInfo: ImageInfo(
                        height: image.map { UInt64($0.size.height) }, width: image.map { UInt64($0.size.width) },
                        mimetype: attachment.mimeType, size: UInt64(attachment.data.count),
                        thumbnailInfo: nil, thumbnailSource: nil,
                        blurhash: blurhash, isAnimated: false
                    ),
                    source: attachment.uploadSource, caption: nil, formattedCaption: nil, thumbnailSource: nil
                ))
            } else if attachment.isVideo {
                let meta = await attachment.avMetadata()
                let blurhash = await attachment.videoBlurhash()
                itemInfos.append(.video(
                    videoInfo: VideoInfo(
                        duration: meta.duration, height: meta.height, width: meta.width,
                        mimetype: attachment.mimeType, size: UInt64(attachment.data.count),
                        thumbnailInfo: nil, thumbnailSource: nil, blurhash: blurhash
                    ),
                    source: attachment.uploadSource, caption: nil, formattedCaption: nil, thumbnailSource: nil
                ))
            } else if attachment.isAudio {
                let meta = await attachment.avMetadata()
                itemInfos.append(.audio(
                    audioInfo: AudioInfo(duration: meta.duration, size: UInt64(attachment.data.count), mimetype: attachment.mimeType),
                    source: attachment.uploadSource, caption: nil, formattedCaption: nil
                ))
            } else {
                itemInfos.append(.file(
                    fileInfo: FileInfo(mimetype: attachment.mimeType, size: UInt64(attachment.data.count), thumbnailInfo: nil, thumbnailSource: nil),
                    source: attachment.uploadSource, caption: nil, formattedCaption: nil
                ))
            }
        }

        let params = GalleryUploadParameters(caption: caption, formattedCaption: nil, mentions: nil, inReplyTo: replyToId)
        do {
            let handle = try innerTimeline.sendGallery(params: params, itemInfos: itemInfos)
            try await handle.join()
        } catch {
            attachmentError = "Failed to send gallery: \(error.localizedDescription)"
            Logger.viewCycle.error("failed to send gallery: \(error)")
        }
    }

    // MARK: - Add attachments

    private func addAttachments(_ attachments: [PendingAttachment]) async {
        let limit = await maxUploadSize
        for attachment in attachments {
            if attachment.data.count > limit {
                attachmentError = "\(attachment.filename) exceeds the \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)) upload limit"
                continue
            }
            pendingAttachments.append(attachment)
        }
    }

    private func handlePasteImage() {
        guard let attachment = PendingAttachment.fromPasteboard() else { return }
        Task { await addAttachments([attachment]) }
    }

    private func handleFilePicker(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let attachments = urls.compactMap { PendingAttachment.fromFileURL($0) }
        Task { await addAttachments(attachments) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: "public.item") { url, _ in
                guard let url else { return }
                if let attachment = PendingAttachment.fromFileURL(url) {
                    Task { @MainActor in await addAttachments([attachment]) }
                }
            }
        }
        return true
    }

    // MARK: - Drafts

    private func saveDraft() async {
        guard isDraftLoaded else { return }
        if chatInput.isEmpty && replyTo == nil {
            Logger.viewCycle.debug("clearing draft")
            do {
                try await room.clearComposerDraft(threadRoot: timeline.focusedThreadId)
            } catch {
                Logger.viewCycle.error("failed to clear draft: \(error)")
            }
            return
        }

        let draftType: ComposerDraftType
        if let replyTo {
            draftType = .reply(eventId: replyTo.eventOrTransactionId.id)
        } else {
            draftType = .newMessage
        }
        let draft = ComposerDraft(
            plainText: chatInput,
            htmlText: nil,
            draftType: draftType,
            attachments: []
        )
        do {
            try await room.saveComposerDraft(draft: draft, threadRoot: timeline.focusedThreadId)
        } catch {
            Logger.viewCycle.error("failed save draft: \(error)")
        }
    }

    private func loadDraft() async {
        guard !isDraftLoaded else { return }
        do {
            guard let draft = try await room.loadComposerDraft(threadRoot: timeline.focusedThreadId) else {
                isDraftLoaded = true
                return
            }
            self.chatInput = draft.plainText
            switch draft.draftType {
            case .reply(eventId: let eventId):
                guard let innerTimeline = timeline.timeline else {
                    isDraftLoaded = false
                    return
                }
                do {
                    let item = try await innerTimeline.getEventTimelineItemByEventId(eventId: eventId)
                    self.timeline.sendReplyTo = item
                } catch {
                    Logger.viewCycle.error("failed to resolve reply target: \(error)")
                }
            case .newMessage, .edit:
                isDraftLoaded = true
                return
            }
        } catch {
            Logger.viewCycle.error("failed to load draft: \(error)")
        }
        isDraftLoaded = true
    }

    private func chatInputChanged() async {
        guard isDraftLoaded else { return }
        if !chatInput.isEmpty {
            do {
                try await room.typingNotice(isTyping: !chatInput.isEmpty)
            } catch {
                Logger.viewCycle.warning("Failed to send typing notice: \(error)")
            }
        }
        await saveDraft()
    }

    var replyEmbeddedDetails: EmbeddedEventDetails? {
        guard let replyTo else { return nil }
        return .ready(content: replyTo.content, sender: replyTo.sender, senderProfile: replyTo.senderProfile, timestamp: replyTo.timestamp, eventOrTransactionId: replyTo.eventOrTransactionId)
    }

    // MARK: - View

    @ViewBuilder
    private var inputRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Button(action: { showFilePicker = true }) {
                Image(systemName: "paperclip")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Attach files")

            if isSending {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else {
                ChatTextInput(
                    text: $chatInput,
                    fontSize: CGFloat(fontSize),
                    isDisabled: !isDraftLoaded,
                    onSubmit: { Task { await sendMessage() } },
                    onImagePaste: handlePasteImage
                )
            }
        }
        .padding(10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let replyEmbeddedDetails {
                EmbeddedMessageView(embeddedEvent: replyEmbeddedDetails) {
                    replyTo = nil
                }
            }

            if let error = attachmentError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error).font(.caption)
                    Spacer()
                    Button("Dismiss") { attachmentError = nil }
                        .buttonStyle(.plain)
                        .font(.caption)
                }
                .padding(8)
            }

            // Attachment previews
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            AttachmentPreviewCell(attachment: attachment) {
                                pendingAttachments.removeAll { $0.id == attachment.id }
                            }
                        }
                    }
                    .padding(8)
                }
            }

            // Input row
            inputRow
        }
        .onExitCommand {
            if !pendingAttachments.isEmpty {
                pendingAttachments.removeAll()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.image, .movie, .audio, .data], allowsMultipleSelection: true, onCompletion: handleFilePicker)
        .font(.system(size: .init(fontSize)))
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(4)
        .lineSpacing(2)
        .frame(minHeight: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .task(id: chatInput) {
            await chatInputChanged()
        }
        .task(id: replyTo?.eventOrTransactionId) {
            await saveDraft()
        }
        .task(id: timeline.timeline != nil) {
            await loadDraft()
        }
        .pointerStyle(.horizontalText)
        .padding([.horizontal, .bottom], 10)
    }
}

// MARK: - Attachment preview cell

private struct AttachmentPreviewCell: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let preview = attachment.preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(6)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "doc")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(attachment.filename)
                        .font(.system(size: 9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 80, height: 80)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }
}

/* #Preview {
     ChatInputView()
 } */
