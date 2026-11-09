import SwiftUI
import AppKit

/// Single-line, borderless text field that accepts only plain text.
///
/// A focused SwiftUI `TextField` edits through AppKit's shared field editor,
/// which accepts dropped files and types their local path into the field. The
/// share label is stored on the server in plaintext, so a path must never land
/// there by accident. This field edits through its own field editor that takes
/// plain-text drags and pastes only: typing, pasting text and dragging text in
/// still work, while file drops fall through to the composer window, which adds
/// them to the file list.
struct PlainTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let font: NSFont
    let textColor: NSColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = TextOnlyTextField(frame: .zero)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byClipping
        field.font = font
        field.textColor = textColor
        field.placeholderString = placeholder
        field.stringValue = text
        field.isEnabled = context.environment.isEnabled
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = context.environment.isEnabled
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        // Only programmatic changes reach this branch: typing updates the
        // binding first, so the two already match.
        if field.stringValue != text { field.stringValue = text }
    }

    /// Fills the offered width; the height is the field's natural line height.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PlainTextField
        init(_ parent: PlainTextField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

/// `NSTextField` whose cell edits through `TextOnlyFieldEditor`.
private final class TextOnlyTextField: NSTextField {
    override class var cellClass: AnyClass? {
        get { TextOnlyTextFieldCell.self }
        set { super.cellClass = newValue }
    }
}

private final class TextOnlyTextFieldCell: NSTextFieldCell {
    /// One editor per field; AppKit asks for it each time editing begins.
    private var editor: TextOnlyFieldEditor?

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if let editor { return editor }
        let made = TextOnlyFieldEditor()
        made.isFieldEditor = true
        editor = made
        return made
    }
}

/// Field editor that reads only plain strings from drags and the pasteboard,
/// so it never registers for file-URL drags.
private final class TextOnlyFieldEditor: NSTextView {
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
}
