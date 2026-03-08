import SwiftUI

public struct AttributedTextView: NSViewRepresentable {
    public let attributedString: NSAttributedString

    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }

    public func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()

        /* textField.isEditable = false
         textField.isSelectable = true
         textField.drawsBackground = false */
        
        textField.attributedStringValue = attributedString
        
        // 1. Remove the "Boxy" look
        textField.isBezeled = false
        textField.isBordered = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        
        // 2. Behavior settings
        textField.isEditable = false
        textField.isSelectable = true // Allows users to copy text
        
        // 3. Wrapping logic
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false // Forces vertical expansion instead of horizontal scrolling
        textField.lineBreakMode = .byWordWrapping
        
        // 4. Layout Priority
        // This helps SwiftUI understand it should stretch vertically
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)

        return textField
    }

    public func updateNSView(_ textField: NSTextField, context: Context) {
        textField.attributedStringValue = attributedString
        
        textField.preferredMaxLayoutWidth = textField.frame.width
        
        // unsafe textView.textStorage?.setAttributedString(attributedString)
        
        // Tell AppKit to recalculate the size now that text has changed
        // textView.invalidateIntrinsicContentSize()
    }
}

public class FittableTextView: NSTextView {
    override public var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return .zero
        }

        // Force layout calculation
        layoutManager.ensureLayout(for: textContainer)
        
        // Get the bounding box of the used glyphs
        let usedRect = layoutManager.usedRect(for: textContainer)
        
        return NSSize(width: NSView.noIntrinsicMetric, height: usedRect.height)
    }
}
