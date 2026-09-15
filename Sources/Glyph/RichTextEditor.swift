// ============================================================
// Glyph — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import SwiftMath
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export

struct RichTextEditor: NSViewRepresentable {
    let viewModel: EditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = GlyphTextView()
        textView.delegate = context.coordinator
        textView.editorViewModel = viewModel
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.isRichText = true
        textView.usesRuler = false
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        if #available(macOS 14.0, *) {
            textView.inlinePredictionType = .no
        }
        textView.allowsUndo = true
        textView.font = EditorTheme.body
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(
            width: EditorTheme.minimumSideInset,
            height: EditorTheme.topInset
        )
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )

        textView.typingAttributes = EditorTheme.bodyAttributes

        scrollView.documentView = textView

        // Store reference on the view model
        viewModel.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? GlyphTextView else { return }
        // Equation bitmaps bake in their text colour, so a light/dark switch has to
        // rebuild them. `colorScheme` drives this update.
        let isDark = context.environment.colorScheme == .dark
        if context.coordinator.lastRenderedDarkMode != isDark {
            context.coordinator.lastRenderedDarkMode = isDark
            invalidateMathImageCache()
            textView.refreshEquationImages()
        }
    }

    // MARK: Coordinator (NSTextViewDelegate)

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let viewModel: EditorViewModel
        /// Tracks the appearance the current equation bitmaps were rendered for.
        var lastRenderedDarkMode: Bool?

        /// A SwiftUI-hosted window supplies no undo manager, so the text view has to
        /// own one. Without this, Command-Z did nothing anywhere in the editor.
        let textUndoManager = UndoManager()

        func undoManager(for view: NSTextView) -> UndoManager? { textUndoManager }

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            // An undo is a rejection. Re-rendering the equation, or immediately
            // offering the same suggestion again, would fight the user.
            let isReverting = textUndoManager.isUndoing || textUndoManager.isRedoing
            if isReverting {
                (notification.object as? GlyphTextView)?.clearSuggestion()
            } else {
                viewModel.scanAndRenderRawLatex()
                viewModel.requestSuggestion()
            }
            if let textView = notification.object as? GlyphTextView {
                // The first line is the title, and an equation's style depends on
                // whether it still has its line to itself.
                textView.enforceTitleStyle()
                textView.restyleEquationsAroundCaret()
            }
            viewModel.noteContentDidChange()
        }

        private var activeEditPopover: NSPopover?
        private var lastSelectedIndex: Int? = nil

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let ts = tv.textStorage else { return }
            
            viewModel.updateFormattingState()

            // Check if selection contains exactly one character containing a LaTeX attachment
            let range = tv.selectedRange()
            guard range.length == 1,
                  range.location + range.length <= ts.length else {
                lastSelectedIndex = nil
                return
            }
            
            if lastSelectedIndex == range.location {
                return
            }
            lastSelectedIndex = range.location
            
            if let latexSource = ts.attribute(.latexSource, at: range.location, effectiveRange: nil) as? String {
                showPopover(for: tv, at: range.location, source: latexSource)
            }
        }

        func textView(_ textView: NSTextView, clickedOn cell: any NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int) {
            guard let textStorage = textView.textStorage,
                  let latexSource = textStorage.attribute(.latexSource, at: charIndex, effectiveRange: nil) as? String else {
                return
            }
            showPopover(for: textView, at: charIndex, source: latexSource)
        }

        private func showPopover(for tv: NSTextView, at charIndex: Int, source latexSource: String) {
            if let active = activeEditPopover {
                active.performClose(nil)
                activeEditPopover = nil
            }
            
            guard let layoutManager = tv.layoutManager,
                  let textContainer = tv.textContainer else { return }
            
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let origin = tv.textContainerOrigin
            let cellFrame = rect.offsetBy(dx: origin.x, dy: origin.y)
            
            let popover = NSPopover()
            popover.behavior = .transient
            self.activeEditPopover = popover
            
            let editView = LatexEditPopoverView(
                initialLatex: latexSource,
                onSave: { [weak tv, weak self] newLatex in
                    guard let tv, let ts = tv.textStorage,
                          charIndex < ts.length,
                          let image = createMathImage(for: newLatex) else {
                        popover.performClose(nil)
                        self?.activeEditPopover = nil
                        return
                    }
                    let replacement = mathAttachmentString(
                        image: image,
                        source: newLatex,
                        font: tv.font ?? .systemFont(ofSize: 18),
                        includeTrailingSpace: false
                    )
                    let range = NSRange(location: charIndex, length: 1)
                    if tv.shouldChangeText(in: range, replacementString: replacement.string) {
                        ts.beginEditing()
                        ts.replaceCharacters(in: range, with: replacement)
                        ts.endEditing()
                        tv.didChangeText()
                    }
                    popover.performClose(nil)
                    self?.activeEditPopover = nil
                    self?.lastSelectedIndex = nil
                },
                onCancel: { [weak self] in
                    popover.performClose(nil)
                    self?.activeEditPopover = nil
                    self?.lastSelectedIndex = nil
                }
            )
            
            popover.contentViewController = NSHostingController(rootView: editView)
            popover.show(relativeTo: cellFrame, of: tv, preferredEdge: .maxY)
        }
    }
}
