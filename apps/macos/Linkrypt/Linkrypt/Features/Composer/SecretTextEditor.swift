import SwiftUI
import AppKit

/// Plain-text editor for the secret box.
///
/// SwiftUI's `TextEditor` wraps an `NSTextView` that accepts dropped file URLs
/// (it inserts the file's path into the text), which would swallow file drops
/// before the composer window can turn them into a file share. This editor
/// accepts only plain-text drags and pastes, so file drops fall through to the
/// composer. It also keeps the secret verbatim: no rich text, no smart quotes
/// or dashes, no automatic substitutions, no spell checking.
struct SecretTextEditor: NSViewRepresentable {
    @Binding var text: String

    private static let font: NSFont = NSFont(name: "JetBrains Mono", size: 12.5)
        ?? .monospacedSystemFont(ofSize: 12.5, weight: .regular)
    /// Attributes for every character in the box, including programmatically
    /// inserted text (a plain-String replacement would carry none and render
    /// as default black on the dark background).
    private static var attributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor(LK.fg)]
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlainTextOnlyView(usingTextLayoutManager: false)   // TextKit 1: undo/redo notify the binding
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.enabledTextCheckingTypes = 0   // no spelling, grammar, link, date or other text checking
        textView.smartInsertDeleteEnabled = false
        // Secrets stay private: no inline predictions, no Writing Tools (which can
        // send text to a model), no completions.
        textView.inlinePredictionType = .no
        textView.writingToolsBehavior = .none
        textView.isEditable = context.environment.isEnabled
        textView.isSelectable = context.environment.isEnabled
        textView.drawsBackground = false
        textView.font = Self.font
        textView.textColor = NSColor(LK.fg)
        textView.insertionPointColor = NSColor(LK.fg)
        textView.typingAttributes = Self.attributes
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView else { return }
        textView.isEditable = context.environment.isEnabled
        textView.isSelectable = context.environment.isEnabled
        guard textView.string != text else { return }
        // Programmatic change (e.g. "load file…"): go through the text system so
        // the undo manager records a coherent entry. Assigning `string` directly
        // leaves earlier undo entries pointing at ranges that no longer exist,
        // and Cmd-Z then raises NSRangeException.
        let whole = NSRange(location: 0, length: textView.textStorage?.length ?? 0)
        textView.breakUndoCoalescing()   // the load is its own undo step, never merged into typing
        if textView.shouldChangeText(in: whole, replacementString: text) {
            // The flag keeps didChangeText() from writing back into the binding
            // while SwiftUI is mid-update.
            context.coordinator.programmatic = true
            textView.textStorage?.replaceCharacters(
                in: whole, with: NSAttributedString(string: text, attributes: Self.attributes))
            textView.didChangeText()
            context.coordinator.programmatic = false
            textView.typingAttributes = Self.attributes
            // The only programmatic change is "load file…"; the Edit menu reads "Undo Load File".
            context.coordinator.undo.setActionName(String(localized: "Load File"))
        }
    }

    /// The box is torn down on a switch to the file tab, but AppKit can keep the
    /// text view alive. Its undo entries live on the box's own stack (see
    /// `Coordinator.undo`), so clearing that stack here means Cmd-Z elsewhere
    /// can never rewrite the hidden secret. The cost: undo history resets on a
    /// tab switch.
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? NSTextView)?.delegate = nil
        coordinator.undo.removeAllActions()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SecretTextEditor
        var programmatic = false
        /// The box's own undo stack, instead of the window's shared one.
        let undo = UndoManager()
        init(_ parent: SecretTextEditor) { self.parent = parent }
        func undoManager(for view: NSTextView) -> UndoManager? { undo }
        func textDidChange(_ notification: Notification) {
            guard !programmatic else { return }
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// An `NSTextView` that takes only plain strings from drags and the pasteboard.
private final class PlainTextOnlyView: NSTextView {
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { [.string] }
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
}
