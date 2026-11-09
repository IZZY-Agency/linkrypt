import SwiftUI
import AppKit
import ObjectiveC

/// Passphrase field: AppKit's secure text field, with its secure field editor
/// left untouched, that refuses to type a dropped file's path.
///
/// While focused, the secure field editor accepts file drags and inserts the
/// file's path into the masked passphrase, where the sender cannot see it. The
/// field vetoes exactly that edit (see `PassphraseDropVeto`) and hands those
/// files to `onFileDrop`, so they reach the composer's file list instead.
/// Typing and pasting are unaffected.
struct PassphraseField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let font: NSFont
    let textColor: NSColor
    let onFileDrop: @MainActor ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = DropVetoSecureTextField(frame: .zero)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.font = font
        field.textColor = textColor
        field.placeholderString = placeholder
        field.stringValue = text
        field.isEnabled = context.environment.isEnabled
        field.onFileDrop = onFileDrop
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = context.environment.isEnabled
        (field as? DropVetoSecureTextField)?.onFileDrop = onFileDrop
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
        if field.stringValue != text { field.stringValue = text }
    }

    /// Fills the offered width; the height is the field's natural line height.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSecureTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? nsView.intrinsicContentSize.width,
               height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PassphraseField
        init(_ parent: PassphraseField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
    }
}

/// The text field is its field editor's delegate, so it sees every edit
/// before it is applied, including the insertion that ends a drag.
private final class DropVetoSecureTextField: NSSecureTextField {
    var onFileDrop: (@MainActor ([URL]) -> Void)?

    // The selector is spelled out: a subclass method does not inherit the
    // protocol's Objective-C name, and AppKit looks up exactly this one.
    @objc(textView:shouldChangeTextInRange:replacementString:)
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        if let replacementString,
           let files = PassphraseDropVeto.droppedFiles(producing: replacementString, eventType: NSApp.currentEvent?.type,
                                                       dragPasteboard: NSPasteboard(name: .drag)) {
            if let onFileDrop {
                DispatchQueue.main.async { MainActor.assumeIsolated { onFileDrop(files) } }
            }
            return false
        }
        return PassphraseDropVeto.inheritedAnswer(self, selector: PassphraseDropVeto.shouldChangeSelector,
                                                  textView: textView, range: affectedCharRange,
                                                  replacement: replacementString)
    }
}

/// The two decisions behind the passphrase field's drop veto.
enum PassphraseDropVeto {
    static let shouldChangeSelector = NSSelectorFromString("textView:shouldChangeTextInRange:replacementString:")

    /// The files whose drop produced `replacement`, or nil when this edit is
    /// anything else. An edit counts as a file drop only when it does not come
    /// from a keystroke (typing and Cmd-V are never vetoed) and its text,
    /// without surrounding whitespace, is exactly what the field editor inserts
    /// for the files on the drag pasteboard: one file's path, or all of their
    /// paths joined by newlines. The drag pasteboard keeps the last drag from any
    /// app, so a mere overlap with its contents (a "/" left there by dragging
    /// the startup disk) must not veto anything.
    static func droppedFiles(producing replacement: String, eventType: NSEvent.EventType?,
                             dragPasteboard: NSPasteboard) -> [URL]? {
        guard eventType != .keyDown else { return nil }
        let text = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let objects = dragPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ?? []
        let files = objects.compactMap { $0 as? URL }.filter { !$0.path.isEmpty }
        guard !files.isEmpty else { return nil }
        if text == files.map(\.path).joined(separator: "\n") { return files }
        if let one = files.first(where: { $0.path == text }) { return [one] }
        return nil
    }

    /// AppKit's own answer for an edit the veto lets through. NSTextField
    /// implements this delegate method privately, so `super` cannot reach it.
    /// When an OS has no such method, the edit is allowed.
    @MainActor
    static func inheritedAnswer(_ field: NSTextField, selector: Selector, textView: NSTextView,
                                range: NSRange, replacement: String?) -> Bool {
        // class_getMethodImplementation never returns nil (it falls back to the
        // forwarding IMP), so the method's existence is checked first.
        guard class_getInstanceMethod(NSSecureTextField.self, selector) != nil,
              let imp = class_getMethodImplementation(NSSecureTextField.self, selector) else { return true }
        typealias Inherited = @convention(c) (AnyObject, Selector, NSTextView, NSRange, NSString?) -> Bool
        return unsafeBitCast(imp, to: Inherited.self)(field, selector, textView, range, replacement as NSString?)
    }
}
