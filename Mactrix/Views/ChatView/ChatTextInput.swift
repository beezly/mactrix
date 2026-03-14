import AppKit
import SwiftUI

struct ChatTextInput: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var isDisabled: Bool
    var onSubmit: () -> Void
    var onImagePaste: () -> Void

    private let maxHeight: CGFloat = 120

    func makeNSView(context: Context) -> PastableTextView {
        let textView = PastableTextView()
        textView.delegate = context.coordinator
        textView.onImagePaste = onImagePaste
        textView.isEditable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: fontSize)
        textView.drawsBackground = false
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainerInset = .zero
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        return textView
    }

    func updateNSView(_ textView: PastableTextView, context: Context) {
        if textView.string != text {
            textView.string = text
            textView.invalidateIntrinsicContentSize()
        }
        textView.font = .systemFont(ofSize: fontSize)
        textView.isEditable = !isDisabled
        textView.onImagePaste = onImagePaste
        context.coordinator.onSubmit = onSubmit
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatTextInput
        var onSubmit: () -> Void

        init(parent: ChatTextInput) {
            self.parent = parent
            self.onSubmit = parent.onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PastableTextView else { return }
            parent.text = textView.string
            textView.invalidateIntrinsicContentSize()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

class PastableTextView: NSTextView {
    var onImagePaste: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Intercept ⌘V before the responder chain rejects it
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let rect = layoutManager.usedRect(for: textContainer)
        let height = min(rect.height + textContainerInset.height * 2, 120)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, font?.pointSize ?? 13 + 4))
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let hasImage = pb.availableType(from: [.png, .init("public.jpeg"), .fileURL]) != nil
        let hasText = pb.string(forType: .string) != nil

        if hasImage && !hasText {
            onImagePaste?()
        } else {
            super.paste(sender)
        }
    }
}
