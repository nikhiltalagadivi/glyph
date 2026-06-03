// ============================================================
// TabNote — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
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

        let textView = TabNoteTextView()
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
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 18)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 72, height: 72)
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

        // Default typing attributes
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ]

        scrollView.documentView = textView

        // Store reference on the view model
        viewModel.textView = textView

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // No SwiftUI-driven updates needed; text view manages its own state
    }

    // MARK: Coordinator (NSTextViewDelegate)

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let viewModel: EditorViewModel

        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }

        func textDidChange(_ notification: Notification) {
            viewModel.requestSuggestion()
        }

        private var activeEditPopover: NSPopover?
        private var lastSelectedIndex: Int? = nil

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView,
                  let ts = tv.textStorage else { return }
            
            if let font = tv.typingAttributes[.font] as? NSFont, font.pointSize < 18 {
                tv.typingAttributes[.font] = NSFont.systemFont(ofSize: 18)
            }
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
                    guard let tv = tv, let ts = tv.textStorage else { return }
                    if let newImage = createMathImage(for: newLatex) {
                        ts.beginEditing()
                        
                        let newAttachment = NSTextAttachment()
                        newAttachment.image = newImage
                        
                        let editorFont = tv.font ?? NSFont.systemFont(ofSize: 18)
                        let descent = editorFont.descender
                        let imgHeight = newImage.size.height
                        let lineHeight = editorFont.ascender - editorFont.descender
                        let yOffset = descent - (imgHeight - lineHeight) / 2
                        newAttachment.bounds = CGRect(origin: CGPoint(x: 0, y: yOffset), size: newImage.size)
                        
                        let attrStr = NSMutableAttributedString(attachment: newAttachment)
                        attrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 18), range: NSRange(location: 0, length: 1))
                        attrStr.addAttribute(.latexSource, value: newLatex, range: NSRange(location: 0, length: attrStr.length))
                        let normalAttrs = [
                            .font: NSFont.systemFont(ofSize: 18),
                            .foregroundColor: NSColor.labelColor
                        ] as [NSAttributedString.Key : Any]
                        attrStr.append(NSAttributedString(string: " ", attributes: normalAttrs))
                        
                        ts.replaceCharacters(in: NSRange(location: charIndex, length: 1), with: attrStr)
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

// MARK: - Vertically Centered Text Field Cell & Glass Status Label

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds theRect: NSRect) -> NSRect {
        let newRect = super.drawingRect(forBounds: theRect)
        let textSize = cellSize(forBounds: theRect)
        let yOffset = (newRect.height - textSize.height) / 2
        if yOffset > 0 {
            return NSRect(x: newRect.minX, y: newRect.minY + yOffset, width: newRect.width, height: newRect.height - yOffset)
        }
        return newRect
    }
}

