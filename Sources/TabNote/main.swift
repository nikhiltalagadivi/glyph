// ============================================================
// TabNote — Freewriting with AI Tab Completion
// macOS 26 · SwiftUI · Liquid Glass · Ollama
// ============================================================

import AppKit
import SwiftUI
import LaTeXSwiftUI
import UniformTypeIdentifiers

// Custom key to store LaTeX source on text attachments for Markdown export
extension NSAttributedString.Key {
    static let latexSource = NSAttributedString.Key("com.tabnote.latexSource")
}

// MARK: - App Entry Point

@main
struct TabNoteApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            EditorScreen()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowStyle(.automatic)
    }
}

// MARK: - Main Editor Screen

struct EditorScreen: View {
    @State private var viewModel = EditorViewModel()

    var body: some View {
        ZStack(alignment: .center) {
            // Full-bleed rich text editor
            RichTextEditor(viewModel: viewModel)
                .ignoresSafeArea()

            // Top Right Thinking Indicator
            VStack {
                HStack {
                    Spacer()
                    if viewModel.statusMessage == "thinking…" {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .background(.regularMaterial, in: Circle())
                            .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Spacer()
            }
            .padding(16)
            .animation(.smooth(duration: 0.25), value: viewModel.statusMessage == "thinking…")

            // Floating UI overlays
            VStack(spacing: 0) {
                // Glass formatting toolbar
                FormattingToolbar(viewModel: viewModel)
                    .padding(.top, 12)

                Spacer()

                // Glass status pill
                if !viewModel.statusMessage.isEmpty && viewModel.statusMessage != "thinking…" && viewModel.statusMessage != "⇥ Tab" {
                    StatusPill(
                        message: viewModel.statusMessage,
                        isHighlighted: viewModel.currentSuggestion != nil
                    )
                    .padding(.bottom, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .padding(.horizontal, 16)
            .animation(.smooth(duration: 0.25), value: viewModel.statusMessage.isEmpty || viewModel.statusMessage == "thinking…" || viewModel.statusMessage == "⇥ Tab")
        }
        .task {
            await viewModel.startupAI()
        }
    }
}

// MARK: - Formatting Toolbar

struct FormattingToolbar: View {
    let viewModel: EditorViewModel

    var body: some View {
        HStack(spacing: 4) {
            FormatButton(icon: "bold", isActive: viewModel.isBold) {
                viewModel.toggleBold()
            }
            FormatButton(icon: "italic", isActive: viewModel.isItalic) {
                viewModel.toggleItalic()
            }
            FormatButton(icon: "underline", isActive: viewModel.isUnderlined) {
                viewModel.toggleUnderline()
            }
            FormatButton(icon: "strikethrough", isActive: viewModel.isStrikethrough) {
                viewModel.toggleStrikethrough()
            }
            
            Divider()
                .frame(height: 18)
                .padding(.horizontal, 4)
            
            FormatButton(icon: "arrow.up.doc", isActive: false) {
                viewModel.exportAsMarkdown()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }
}

private struct FormatButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: isActive ? .bold : .medium))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Status Pill

struct StatusPill: View {
    let message: String
    let isHighlighted: Bool

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isHighlighted ? .primary : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Editor View Model

@Observable
@MainActor
final class EditorViewModel {
    // Text view reference (set by NSViewRepresentable)
    weak var textView: TabNoteTextView?

    // Current suggestion state
    var currentSuggestion: SuggestionResult?
    var lastAcceptedSuggestionText: String?
    var statusMessage = "" {
        didSet {
            textView?.updateStatusMessage(statusMessage)
        }
    }

    // Formatting state (reflects selection / typing attributes)
    var isBold = false
    var isItalic = false
    var isUnderlined = false
    var isStrikethrough = false

    // Engine
    private let engine = OllamaSuggestionEngine(runtime: BundledOllamaRuntime())
    private var suggestionTask: Task<Void, Never>?
    private var requestID: UInt64 = 0

    // MARK: Formatting

    func toggleBold() {
        textView?.toggleBold()
        updateFormattingState()
        refocusTextView()
    }

    func toggleItalic() {
        textView?.toggleItalic()
        updateFormattingState()
        refocusTextView()
    }

    func toggleUnderline() {
        textView?.toggleUnderline()
        updateFormattingState()
        refocusTextView()
    }

    func toggleStrikethrough() {
        textView?.toggleStrikethrough()
        updateFormattingState()
        refocusTextView()
    }

    func updateFormattingState() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let attrs: [NSAttributedString.Key: Any]

        if range.length > 0, let ts = tv.textStorage, range.location < ts.length {
            attrs = ts.attributes(at: range.location, effectiveRange: nil)
        } else {
            attrs = tv.typingAttributes
        }

        if let font = attrs[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            isBold = traits.contains(.bold)
            isItalic = traits.contains(.italic)
        } else {
            isBold = false
            isItalic = false
        }
        isUnderlined = (attrs[.underlineStyle] as? Int ?? 0) != 0
        isStrikethrough = (attrs[.strikethroughStyle] as? Int ?? 0) != 0
    }

    private func refocusTextView() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    // MARK: Suggestions

    func startupAI() async {
        let pollTask = Task {
            while !Task.isCancelled {
                let msg = await engine.statusMessage()
                if self.statusMessage != msg && self.currentSuggestion == nil {
                    self.statusMessage = msg
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        await engine.warmup()
        pollTask.cancel()
        if self.currentSuggestion == nil {
            self.statusMessage = ""
        }
    }

    func requestSuggestion() {
        suggestionTask?.cancel()
        requestID &+= 1
        let currentID = requestID

        guard let tv = textView else { return }
        let text = tv.string
        let cursor = tv.selectedRange().location
        let selLen = tv.selectedRange().length

        // Need at least 3 chars and no selection
        guard selLen == 0, text.count >= 3 else {
            currentSuggestion = nil
            if self.statusMessage == "thinking…" || self.statusMessage == "⇥ Tab" {
                self.statusMessage = ""
            }
            tv.clearSuggestion()
            return
        }

        // Prevent immediate re-triggering during suggestion insertion
        if tv.isInsertingSuggestion {
            return
        }

        // Check if cursor is immediately preceded by the text attachment character 0xFFFC
        if cursor > 0 {
            let nsText = text as NSString
            for offset in 1...min(2, cursor) {
                if nsText.character(at: cursor - offset) == 0xFFFC {
                    currentSuggestion = nil
                    if self.statusMessage == "thinking…" || self.statusMessage == "⇥ Tab" {
                        self.statusMessage = ""
                    }
                    tv.clearSuggestion()
                    return
                }
            }
        }

        // Don't show "thinking..." immediately to avoid flicker while typing
        if self.statusMessage == "⇥ Tab" {
            self.statusMessage = ""
        }

        let prefix = (text as NSString).substring(to: cursor)
        let isSlashCommand = prefix.range(of: "(?:\\s|^)/[^\\n]*$", options: .regularExpression) != nil
        let isLocalMath = !isSlashCommand && LocalMathTranslator.translate(text: prefix) != nil
        
        let isInstant = isSlashCommand || isLocalMath
        let debounceMs = isInstant ? 100 : 400

        let snapshot = EditorSnapshot(text: text, cursorOffset: cursor)

        suggestionTask = Task { 
            try? await Task.sleep(for: .milliseconds(debounceMs))
            guard !Task.isCancelled else { return }
            
            // 1. If it's a slash command, we query Ollama using the ultra-fast slash AI!
            if isSlashCommand {
                self.statusMessage = "thinking…"
                let result = await self.engine.suggestSlashAI(for: snapshot)
                let msg = await self.engine.statusMessage()

                guard !Task.isCancelled, currentID == self.requestID else { return }
                guard let tv = self.textView,
                      tv.string == text,
                      tv.selectedRange().location == cursor,
                      tv.selectedRange().length == 0 else { return }

                if let suggestion = result,
                   suggestion.text != self.lastAcceptedSuggestionText,
                   !suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.currentSuggestion = suggestion
                    self.statusMessage = "⇥ Tab"
                    tv.showSuggestion(suggestion)
                } else {
                    self.currentSuggestion = nil
                    self.statusMessage = msg
                    tv.clearSuggestion()
                }
                return
            }
            
            // 2. Otherwise (normal typing), try local translation only
            if let result = await self.engine.suggestLocal(for: snapshot) {
                guard !Task.isCancelled, currentID == self.requestID else { return }
                guard let tv = self.textView,
                      tv.string == text,
                      tv.selectedRange().location == cursor,
                      tv.selectedRange().length == 0 else { return }
                
                if result.text != self.lastAcceptedSuggestionText {
                    self.currentSuggestion = result
                    self.statusMessage = "⇥ Tab"
                    tv.showSuggestion(result)
                    return
                }
            }

            // 3. Fallback to Ollama if it might contain math
            if await self.engine.mightContainMath(prefix) {
                self.statusMessage = "thinking…"
                let result = await self.engine.suggestOllama(for: snapshot)
                let msg = await self.engine.statusMessage()

                guard !Task.isCancelled, currentID == self.requestID else { return }
                guard let tv = self.textView,
                      tv.string == text,
                      tv.selectedRange().location == cursor,
                      tv.selectedRange().length == 0 else { return }

                if let suggestion = result,
                   suggestion.text != self.lastAcceptedSuggestionText,
                   !suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.currentSuggestion = suggestion
                    self.statusMessage = "⇥ Tab"
                    tv.showSuggestion(suggestion)
                    return
                } else {
                    if self.statusMessage == "thinking…" {
                        self.statusMessage = msg
                    }
                }
            }
            
            // 4. Normal typing doesn't match local translation or Ollama -> clear suggestion
            guard !Task.isCancelled, currentID == self.requestID else { return }
            if self.statusMessage == "thinking…" || self.statusMessage == "⇥ Tab" {
                self.statusMessage = ""
            }
            self.textView?.clearSuggestion()
        }
    }

    func didAcceptSuggestion() {
        lastAcceptedSuggestionText = currentSuggestion?.text
        currentSuggestion = nil
        statusMessage = ""
    }

    func didDismissSuggestion() {
        currentSuggestion = nil
        statusMessage = ""
    }

    // MARK: Export

    func exportAsMarkdown() {
        guard let tv = textView, let ts = tv.textStorage else { return }

        var markdown = ""
        let fullRange = NSRange(location: 0, length: ts.length)

        ts.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            // Check for text attachment (rendered LaTeX)
            if attrs[.attachment] is NSTextAttachment {
                // Try to recover stored LaTeX source
                if let latex = attrs[.latexSource] as? String {
                    markdown += latex
                } else {
                    markdown += "[equation]"
                }
                return
            }

            let substring = ts.attributedSubstring(from: range).string

            // Determine formatting
            let font = attrs[.font] as? NSFont
            let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
            let isItalic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? false
            let isUnderline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
            let isStrike = ((attrs[.strikethroughStyle] as? Int) ?? 0) != 0

            var text = substring
            // Apply Markdown formatting (innermost first)
            if isStrike { text = "~~\(text)~~" }
            if isUnderline { text = "<u>\(text)</u>" }
            if isBold && isItalic { text = "***\(text)***" }
            else if isBold { text = "**\(text)**" }
            else if isItalic { text = "_\(text)_" }

            markdown += text
        }

        // Show save panel
        let panel = NSSavePanel()
        panel.title = "Export as Markdown"
        panel.nameFieldStringValue = "Untitled.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
}

// MARK: - Rich Text Editor (NSViewRepresentable)

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

final class GlassStatusLabel: NSTextField {
    nonisolated(unsafe) private var animationTimer: Timer?
    
    var isThinking = false {
        didSet {
            if isThinking {
                startAnimation()
            } else {
                stopAnimation()
            }
            needsDisplay = true
        }
    }
    
    private func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.needsDisplay = true
            }
        }
        // Ensure it runs during scrolling / tracking
        RunLoop.current.add(animationTimer!, forMode: .common)
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    deinit {
        animationTimer?.invalidate()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if isThinking {
            NSGraphicsContext.saveGraphicsState()
            
            let time = CACurrentMediaTime()
            let midX = bounds.width / 2
            let midY = bounds.height / 2
            let radius: CGFloat = 7.0
            
            // Draw track
            let trackPath = NSBezierPath()
            trackPath.appendArc(withCenter: NSPoint(x: midX, y: midY), radius: radius, startAngle: 0, endAngle: 360)
            NSColor.labelColor.withAlphaComponent(0.15).setStroke()
            trackPath.lineWidth = 2.5
            trackPath.stroke()
            
            // Draw spinning arc
            let speed: Double = 1.2
            let startAngle = CGFloat(time * speed * 360).truncatingRemainder(dividingBy: 360)
            let endAngle = startAngle + 100.0 // 100 degree arc
            
            let spinPath = NSBezierPath()
            spinPath.appendArc(withCenter: NSPoint(x: midX, y: midY), radius: radius, startAngle: startAngle, endAngle: endAngle)
            NSColor.labelColor.withAlphaComponent(0.6).setStroke()
            spinPath.lineWidth = 2.5
            spinPath.lineCapStyle = .round
            spinPath.stroke()
            
            NSGraphicsContext.restoreGraphicsState()
        } else {
            super.draw(dirtyRect)
        }
    }
}

// MARK: - TabNote Text View (NSTextView subclass)

class TabNoteTextView: NSTextView {
    weak var editorViewModel: EditorViewModel?

    // Ghost text state
    private var activeSuggestion: SuggestionResult?
    var isInsertingSuggestion = false

    private lazy var ghostLabel: GlassStatusLabel = {
        let cell = VerticallyCenteredTextFieldCell(textCell: "")
        cell.isScrollable = false
        cell.alignment = .left
        
        let field = GlassStatusLabel()
        field.cell = cell
        field.textColor = NSColor.placeholderTextColor.withAlphaComponent(0.45)
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.alphaValue = 0
        return field
    }()

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if ghostLabel.superview == nil {
            addSubview(ghostLabel)
        }
    }

    // MARK: Key Handling

    override func keyDown(with event: NSEvent) {
        // ⌘B / ⌘I / ⌘U / ⌘E keyboard shortcuts
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "b":
                toggleBold()
                editorViewModel?.updateFormattingState()
                return
            case "i":
                toggleItalic()
                editorViewModel?.updateFormattingState()
                return
            case "u":
                toggleUnderline()
                editorViewModel?.updateFormattingState()
                return
            case "e":
                editorViewModel?.exportAsMarkdown()
                return
            default:
                break
            }
        }

        // Tab → accept ghost suggestion
        if event.keyCode == 48, activeSuggestion != nil {
            acceptCurrentSuggestion()
            return
        }

        // Escape → dismiss ghost suggestion
        if event.keyCode == 53, activeSuggestion != nil {
            clearSuggestion()
            return
        }

        // Any other key → clear ghost text before processing
        if activeSuggestion != nil {
            clearSuggestion()
        }

        super.keyDown(with: event)
    }

    // Prevent textDidChange from triggering new suggestions while inserting
    override func didChangeText() {
        super.didChangeText()
        if isInsertingSuggestion { return }
        self.needsDisplay = true
    }

    override func layout() {
        super.layout()
        if activeSuggestion != nil {
            positionGhostLabel()
        }
    }

    // MARK: Ghost Text
    
    private var temporaryHighlightRange: NSRange?

    func showSuggestion(_ suggestion: SuggestionResult) {
        guard window?.firstResponder === self,
              !suggestion.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clearSuggestion()
            return
        }

        activeSuggestion = suggestion
        ghostLabel.isThinking = false
        ghostLabel.alignment = .left
        
        let firstLine = suggestion.text.components(separatedBy: .newlines).first ?? suggestion.text
        let editorFont = self.font ?? .systemFont(ofSize: 18)

        let styled = NSMutableAttributedString()
        if let hlRange = suggestion.replaceRange {
            styled.append(NSAttributedString(
                string: " ⟲ \(firstLine)",
                attributes: [
                    .font: editorFont,
                    .foregroundColor: NSColor.labelColor.withAlphaComponent(0.55)
                ]
            ))
            
            // Highlight the text that will be replaced via custom drawing
            if hlRange.length > 0 && NSMaxRange(hlRange) <= (textStorage?.length ?? 0) {
                self.temporaryHighlightRange = hlRange
                self.needsDisplay = true
            }
        } else {
            styled.append(NSAttributedString(
                string: firstLine,
                attributes: [
                    .font: editorFont,
                    .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.45)
                ]
            ))
        }
        
        let tabImage = createTabKeyImage(font: editorFont)
        let tabAttachment = NSTextAttachment()
        tabAttachment.image = tabImage
        let descent = editorFont.descender
        let yOffset = descent + (editorFont.ascender - descent - tabImage.size.height) / 2
        tabAttachment.bounds = CGRect(x: 0, y: yOffset, width: tabImage.size.width, height: tabImage.size.height)
        
        styled.append(NSAttributedString(string: "  "))
        styled.append(NSAttributedString(attachment: tabAttachment))
        
        ghostLabel.attributedStringValue = styled
        positionGhostLabel()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.ghostLabel.animator().alphaValue = 1
        }
    }

    func clearSuggestion() {
        if temporaryHighlightRange != nil {
            self.temporaryHighlightRange = nil
            self.needsDisplay = true
        }
        
        ghostLabel.isThinking = false
        ghostLabel.alignment = .left
        
        let hadSuggestion = activeSuggestion != nil
        activeSuggestion = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.ghostLabel.animator().alphaValue = 0
        }
        ghostLabel.attributedStringValue = NSAttributedString(string: "")
        if hadSuggestion {
            editorViewModel?.didDismissSuggestion()
        }
    }

    private func acceptCurrentSuggestion() {
        guard let suggestion = activeSuggestion else { return }
        let text = suggestion.text
        let range = selectedRange()

        isInsertingSuggestion = true

        if let deleteRange = suggestion.replaceRange {
            // Safety: validate deleteRange is within textStorage bounds
            let tsLength = textStorage?.length ?? 0
            guard deleteRange.location >= 0,
                  deleteRange.length >= 0,
                  NSMaxRange(deleteRange) <= tsLength else {
                // Range is invalid — fall through to plain insertion
                isInsertingSuggestion = false
                activeSuggestion = nil
                ghostLabel.alphaValue = 0
                ghostLabel.stringValue = ""
                return
            }

            if let image = createMathImage(for: text) {
                let attachment = NSTextAttachment()
                attachment.image = image
                // Compute baseline offset: align bottom of image with font descender
                let editorFont = self.font ?? NSFont.systemFont(ofSize: 18)
                let descent = editorFont.descender // negative, e.g. -4.2
                let imgHeight = image.size.height
                let lineHeight = editorFont.ascender - editorFont.descender
                let yOffset = descent - (imgHeight - lineHeight) / 2
                attachment.bounds = CGRect(origin: CGPoint(x: 0, y: yOffset), size: image.size)
                
                let attrStr = NSMutableAttributedString(attachment: attachment)
                attrStr.addAttribute(.font, value: NSFont.systemFont(ofSize: 18), range: NSRange(location: 0, length: 1))
                // Store original LaTeX source so we can recover it for Markdown export
                attrStr.addAttribute(.latexSource, value: text, range: NSRange(location: 0, length: attrStr.length))
                let normalAttrs = [
                    .font: NSFont.systemFont(ofSize: 18),
                    .foregroundColor: NSColor.labelColor
                ] as [NSAttributedString.Key : Any]
                attrStr.append(NSAttributedString(string: " ", attributes: normalAttrs))
                
                textStorage?.replaceCharacters(in: deleteRange, with: attrStr)
                
                // Keep cursor where it was, or move it if it was inside/after the replaced text
                let newCursorLoc: Int
                if range.location > NSMaxRange(deleteRange) {
                    newCursorLoc = range.location - deleteRange.length + 2
                } else if range.location >= deleteRange.location {
                    newCursorLoc = deleteRange.location + 2
                } else {
                    newCursorLoc = range.location
                }
                setSelectedRange(NSRange(location: newCursorLoc, length: 0))
                
                self.typingAttributes = normalAttrs
                editorViewModel?.updateFormattingState()
            } else {
                let attrText = NSAttributedString(string: text, attributes: typingAttributes)
                textStorage?.replaceCharacters(in: deleteRange, with: attrText)
                
                let newCursorLoc: Int
                if range.location > NSMaxRange(deleteRange) {
                    newCursorLoc = range.location - deleteRange.length + (text as NSString).length
                } else if range.location >= deleteRange.location {
                    newCursorLoc = deleteRange.location + (text as NSString).length
                } else {
                    newCursorLoc = range.location
                }
                setSelectedRange(NSRange(location: newCursorLoc, length: 0))
            }
            
            didChangeText()

        } else {
            if shouldChangeText(in: range, replacementString: text) {
                let attrText = NSAttributedString(string: text, attributes: typingAttributes)
                textStorage?.replaceCharacters(in: range, with: attrText)
                didChangeText()

                let newLoc = range.location + (text as NSString).length
                setSelectedRange(NSRange(location: newLoc, length: 0))
            }
        }

        isInsertingSuggestion = false
        activeSuggestion = nil
        ghostLabel.alphaValue = 0
        ghostLabel.stringValue = ""
        
        // Always ensure typing attributes are reset to normal size
        // This prevents the "small text" bug after accepting a math equation
        let normalFont = NSFont.systemFont(ofSize: 18)
        self.typingAttributes[.font] = normalFont
        self.typingAttributes[.foregroundColor] = NSColor.labelColor
        
        editorViewModel?.didAcceptSuggestion()
    }

    private func positionGhostLabel() {
        guard ghostLabel.attributedStringValue.length > 0,
              let lm = layoutManager,
              let tc = textContainer else { return }

        let cursor = selectedRange().location
        let textLen = textStorage?.length ?? 0

        var cursorX: CGFloat = textContainerInset.width
        var cursorY: CGFloat = textContainerInset.height
        var lineHeight: CGFloat = (font?.pointSize ?? 18) * 1.4

        if textLen == 0 {
            cursorX = textContainerInset.width
            cursorY = textContainerInset.height
        } else {
            let charIndex = min(max(0, cursor), textLen)
            if charIndex == textLen, textStorage?.string.hasSuffix("\n") == true {
                let rect = lm.extraLineFragmentRect
                cursorX = rect.minX + textContainerInset.width
                cursorY = rect.minY + textContainerInset.height
                lineHeight = rect.height
            } else {
                let indexForRect = (charIndex == textLen) ? (textLen - 1) : charIndex
                let glyphIdx = lm.glyphIndexForCharacter(at: indexForRect)
                let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil)
                let rect = lm.boundingRect(forGlyphRange: NSRange(location: glyphIdx, length: 1), in: tc)
                
                cursorY = lineRect.minY + textContainerInset.height
                lineHeight = lineRect.height
                
                if charIndex == textLen {
                    cursorX = rect.maxX + textContainerInset.width
                } else {
                    cursorX = rect.minX + textContainerInset.width
                }
            }
        }

        let maxWidth = max(0, bounds.width - cursorX - textContainerInset.width - 8)
        
        var labelHeight = lineHeight
        var labelY = cursorY
        var labelX = cursorX + 1
        var labelWidth = maxWidth
        
        if ghostLabel.isThinking {
            labelHeight = 22
            labelY = cursorY + (lineHeight - labelHeight) / 2
            labelX = cursorX + 4
            labelWidth = min(36, maxWidth)
        }
        
        ghostLabel.frame = NSRect(
            x: labelX,
            y: labelY,
            width: labelWidth,
            height: labelHeight
        )
    }

    func updateStatusMessage(_ message: String) {
        if activeSuggestion == nil {
            ghostLabel.isThinking = false
            ghostLabel.alignment = .left
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                self.ghostLabel.animator().alphaValue = 0
            }
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        
        guard let lm = layoutManager, let tc = textContainer else { return }
        let origin = textContainerOrigin
        
        if let hlRange = temporaryHighlightRange, hlRange.length > 0 {
            let glyphRange = lm.glyphRange(forCharacterRange: hlRange, actualCharacterRange: nil)
            lm.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: tc) { rect, _ in
                let drawRect = rect.offsetBy(dx: origin.x, dy: origin.y)
                
                NSGraphicsContext.saveGraphicsState()
                
                let paddedRect = drawRect.insetBy(dx: -4, dy: -2)
                let path = NSBezierPath(roundedRect: paddedRect, xRadius: 6, yRadius: 6)
                
                NSColor.labelColor.withAlphaComponent(0.08).setFill()
                path.fill()
                
                NSColor.labelColor.withAlphaComponent(0.12).setStroke()
                path.lineWidth = 1.0
                path.stroke()
                
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    // MARK: Formatting

    func toggleBold() {
        let range = selectedRange()
        if range.length > 0 {
            applyFontTrait(.bold, range: range)
        } else {
            toggleTypingFontTrait(.bold)
        }
    }

    func toggleItalic() {
        let range = selectedRange()
        if range.length > 0 {
            applyFontTrait(.italic, range: range)
        } else {
            toggleTypingFontTrait(.italic)
        }
    }

    func toggleUnderline() {
        let range = selectedRange()
        if range.length > 0 {
            toggleAttribute(.underlineStyle, range: range)
        } else {
            toggleTypingAttribute(.underlineStyle)
        }
    }

    func toggleStrikethrough() {
        let range = selectedRange()
        if range.length > 0 {
            toggleAttribute(.strikethroughStyle, range: range)
        } else {
            toggleTypingAttribute(.strikethroughStyle)
        }
    }

    // MARK: Private Formatting Helpers

    private func applyFontTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        range: NSRange
    ) {
        guard let ts = textStorage else { return }
        let fm = NSFontManager.shared
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask

        ts.beginEditing()
        ts.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            let newFont: NSFont
            if font.fontDescriptor.symbolicTraits.contains(trait) {
                newFont = fm.convert(font, toNotHaveTrait: mask)
            } else {
                newFont = fm.convert(font, toHaveTrait: mask)
            }
            ts.addAttribute(.font, value: newFont, range: attrRange)
        }
        ts.endEditing()
    }

    private func toggleTypingFontTrait(_ trait: NSFontDescriptor.SymbolicTraits) {
        var attrs = typingAttributes
        guard let font = attrs[.font] as? NSFont else { return }
        let fm = NSFontManager.shared
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask

        if font.fontDescriptor.symbolicTraits.contains(trait) {
            attrs[.font] = fm.convert(font, toNotHaveTrait: mask)
        } else {
            attrs[.font] = fm.convert(font, toHaveTrait: mask)
        }
        typingAttributes = attrs
    }

    private func toggleAttribute(
        _ key: NSAttributedString.Key,
        range: NSRange
    ) {
        guard let ts = textStorage else { return }
        ts.beginEditing()

        var hasAttr = false
        ts.enumerateAttribute(key, in: range, options: []) { value, _, _ in
            if let style = value as? Int, style != 0 { hasAttr = true }
        }

        if hasAttr {
            ts.removeAttribute(key, range: range)
        } else {
            ts.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        ts.endEditing()
    }

    private func toggleTypingAttribute(_ key: NSAttributedString.Key) {
        var attrs = typingAttributes
        let current = (attrs[key] as? Int) ?? 0
        if current != 0 {
            attrs.removeValue(forKey: key)
        } else {
            attrs[key] = NSUnderlineStyle.single.rawValue
        }
        typingAttributes = attrs
    }
}

@MainActor
func createMathImage(for markdown: String) -> NSImage? {
    var processed = markdown
    if processed.hasPrefix("$") && processed.hasSuffix("$") && !processed.hasPrefix("$$") {
        processed = "\\(" + processed.dropFirst().dropLast() + "\\)"
    } else if processed.hasPrefix("$$") && processed.hasSuffix("$$") {
        processed = "\\[" + processed.dropFirst(2).dropLast(2) + "\\]"
    }

    // Use slightly larger font to match surrounding 18pt system text
    // (LaTeX rendering is visually smaller than system font at same pt size)
    let view = LaTeX(processed)
        .font(.system(size: 20))
        .foregroundColor(Color(NSColor.textColor))
        .fixedSize()
    
    let renderer = ImageRenderer(content: view)
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0
    return renderer.nsImage
}

// MARK: - LaTeX Editing Popover View

struct LatexEditPopoverView: View {
    @State private var latexText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(initialLatex: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _latexText = State(initialValue: initialLatex)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit LaTeX Equation")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)
            
            TextEditor(text: $latexText)
                .font(.system(.body, design: .monospaced))
                .frame(width: 320, height: 100)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Save") {
                    onSave(latexText)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 344)
    }
}

// MARK: - Local Math Translation Heuristic

struct LocalMathTranslator {
    static let greekLetters = [
        "alpha": "\\alpha", "beta": "\\beta", "gamma": "\\gamma", "delta": "\\delta",
        "epsilon": "\\epsilon", "theta": "\\theta", "lambda": "\\lambda", "mu": "\\mu",
        "sigma": "\\sigma", "omega": "\\omega", "phi": "\\phi", "psi": "\\psi",
        "tau": "\\tau", "rho": "\\rho", "pi": "\\pi", "infinity": "\\infty", "infty": "\\infty"
    ]

    static func translate(text: String) -> (original: String, latex: String)? {
        let lines = text.components(separatedBy: .newlines)
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines), !lastLine.isEmpty else {
            return nil
        }
        
        // 1. Integrals: "integral from X to Y of Z" -> \int_{X}^{Y} Z
        let integralPattern = "(?i)\\bintegral\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)\\s+of\\s+(.+)$"
        if let match = matchRegex(pattern: integralPattern, in: lastLine) {
            let original = match[0]
            let fromVal = cleanExpr(match[1])
            let toVal = cleanExpr(match[2])
            let ofVal = cleanExpr(match[3])
            let latex = "\\( \\int_{\(fromVal)}^{\(toVal)} \(ofVal) \\)"
            return (original, latex)
        }
        
        // 2. Sums: "sum of X from Y to Z"
        let sumPattern1 = "(?i)\\bsum\\s+of\\s+(.+?)\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)$"
        if let match = matchRegex(pattern: sumPattern1, in: lastLine) {
            let original = match[0]
            let expr = cleanExpr(match[1])
            let fromVal = cleanExpr(match[2])
            let toVal = cleanExpr(match[3])
            let latex = "\\( \\sum_{\(fromVal)}^{\(toVal)} \(expr) \\)"
            return (original, latex)
        }
        
        // "sum from Y to Z of X"
        let sumPattern2 = "(?i)\\bsum\\s+from\\s+(\\S+)\\s+to\\s+(\\S+)\\s+of\\s+(.+)$"
        if let match = matchRegex(pattern: sumPattern2, in: lastLine) {
            let original = match[0]
            let fromVal = cleanExpr(match[1])
            let toVal = cleanExpr(match[2])
            let expr = cleanExpr(match[3])
            let latex = "\\( \\sum_{\(fromVal)}^{\(toVal)} \(expr) \\)"
            return (original, latex)
        }
        
        // 3. Limits: "limit as X approaches Y of Z"
        let limitPattern = "(?i)\\blimit\\s+as\\s+(\\S+)\\s+approaches\\s+(\\S+)\\s+of\\s+(.+)$"
        if let match = matchRegex(pattern: limitPattern, in: lastLine) {
            let original = match[0]
            let varVal = cleanExpr(match[1])
            let approachVal = cleanExpr(match[2])
            let expr = cleanExpr(match[3])
            let latex = "\\( \\lim_{\(varVal) \\to \(approachVal)} \(expr) \\)"
            return (original, latex)
        }

        // 4. Fractions: "X over Y" or "X divided by Y"
        let overPattern = "(?i)\\b(.+?)\\s+over\\s+(.+)$"
        if let match = matchRegex(pattern: overPattern, in: lastLine) {
            let original = match[0]
            let num = cleanExpr(match[1])
            let den = cleanExpr(match[2])
            let latex = "\\( \\frac{\(num)}{\(den)} \\)"
            return (original, latex)
        }
        
        // 5. General formulas / equations
        if mightBeMathLine(lastLine) {
            let latex = cleanExpr(lastLine)
            if latex.lowercased() != lastLine.lowercased() {
                let mathWords = ["pi", "squared", "cubed", "plus", "minus", "equals", "times", "dot", "cross", "alpha", "beta", "gamma", "delta", "epsilon", "theta", "lambda", "mu", "sigma", "omega", "phi", "psi", "tau", "rho", "infinity", "vector", "matrix", "sqrt", "root"]
                let words = lastLine.components(separatedBy: .whitespaces)
                var mathStartIndex = words.count - 1
                for (idx, word) in words.enumerated() {
                    let lowerWord = word.lowercased()
                    let cleanWord = lowerWord.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.alphanumerics.inverted))
                    if mathWords.contains(cleanWord)
                        || lowerWord.rangeOfCharacter(from: .decimalDigits) != nil
                        || lowerWord.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^=<>()_")) != nil {
                        mathStartIndex = idx
                        break
                    }
                }
                
                // Backtrack to include preceding single-character variables or simple math terms
                while mathStartIndex > 0 {
                    let prevWord = words[mathStartIndex - 1]
                    let cleanPrev = prevWord.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.alphanumerics.inverted))
                    if cleanPrev.count == 1 || mathWords.contains(cleanPrev.lowercased()) {
                        mathStartIndex -= 1
                    } else {
                        break
                    }
                }
                
                let original = words[mathStartIndex...].joined(separator: " ")
                let cleanMath = cleanExpr(original)
                return (original, "\\( \(cleanMath) \\)")
            }
        }
        
        return nil
    }
    
    private static func mightBeMathLine(_ line: String) -> Bool {
        let mathKeywords = ["squared", "cubed", "plus", "minus", "equals", "times", "dot", "cross", "over", "sum", "integral", "limit", "vector", "matrix", "sqrt", "root"]
        let lower = line.lowercased()
        for kw in mathKeywords {
            if lower.contains(kw) { return true }
        }
        for greek in greekLetters.keys {
            if lower.contains(greek) { return true }
        }
        let mathChars = CharacterSet(charactersIn: "+-*/^=<>()_")
        if lower.rangeOfCharacter(from: mathChars) != nil {
            return true
        }
        return false
    }

    private static func cleanExpr(_ expr: String) -> String {
        var result = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Handle "square root of X" -> \sqrt{X}
        let sqrtPattern = "(?i)\\bsquare\\s+root\\s+of\\s+(.+)$"
        if let match = matchRegex(pattern: sqrtPattern, in: result) {
            let inner = cleanExpr(match[1])
            result = result.replacingOccurrences(of: match[0], with: "\\sqrt{\(inner)}")
        }
        
        // 2. Handle "vector X" -> \mathbf{X}
        let vectorPattern = "(?i)\\bvector\\s+([a-zA-Z0-9]+)"
        while let match = matchRegex(pattern: vectorPattern, in: result) {
            let inner = match[1]
            result = result.replacingOccurrences(of: match[0], with: "\\mathbf{\(inner)}")
        }

        // 3. Handle nested "over" inside cleanExpr
        let overPattern = "(?i)\\b(.+?)\\s+over\\s+(.+)$"
        if let match = matchRegex(pattern: overPattern, in: result) {
            let num = cleanExpr(match[1])
            let den = cleanExpr(match[2])
            result = result.replacingOccurrences(of: match[0], with: "\\frac{\(num)}{\(den)}")
        }

        // Tokenize into words and convert
        var tokens = result.components(separatedBy: .whitespaces)
        var i = 0
        while i < tokens.count {
            let token = tokens[i].lowercased()
            
            // Check for greek letters
            if let latexGreek = greekLetters[token] {
                tokens[i] = latexGreek
            }
            // Check for simple operators
            else if token == "plus" || token == "+" {
                tokens[i] = "+"
            } else if token == "minus" || token == "-" {
                tokens[i] = "-"
            } else if token == "equals" || token == "=" {
                tokens[i] = "="
            } else if token == "dot" || token == "times" {
                tokens[i] = "\\cdot"
            } else if token == "cross" {
                tokens[i] = "\\times"
            }
            // Exponents
            else if token == "squared" {
                if i > 0 {
                    tokens[i-1] = tokens[i-1] + "^2"
                    tokens.remove(at: i)
                    continue
                }
            } else if token == "cubed" {
                if i > 0 {
                    tokens[i-1] = tokens[i-1] + "^3"
                    tokens.remove(at: i)
                    continue
                }
            }
            // Subscripts: "x sub i" -> "x_i"
            else if token == "sub" || token == "subscript" {
                if i > 0 && i < tokens.count - 1 {
                    let next = tokens[i+1]
                    tokens[i-1] = tokens[i-1] + "_\(next)"
                    tokens.remove(at: i + 1)
                    tokens.remove(at: i)
                    continue
                }
            }
            
            i += 1
        }
        
        result = tokens.joined(separator: " ")
        
        // Post-processing cleanup for spacing
        // e.g. "a ^ 2" -> "a^2"
        result = result.replacingOccurrences(of: " \\^ ", with: "^")
        result = result.replacingOccurrences(of: "\\^ ", with: "^")
        result = result.replacingOccurrences(of: " \\^", with: "^")
        
        // variables with digits -> subscript, e.g. "t1" -> "t_1"
        result = result.replacingOccurrences(of: "\\b([a-zA-Z])(\\d+)\\b", with: "$1_$2", options: .regularExpression)
        
        // fractions like "1/2" -> "\frac{1}{2}"
        let fracPattern = "(\\d+)/(\\d+)"
        if let regex = try? NSRegularExpression(pattern: fracPattern) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for m in matches.reversed() {
                let num = ns.substring(with: m.range(at: 1))
                let den = ns.substring(with: m.range(at: 2))
                result = ns.replacingCharacters(in: m.range, with: "\\frac{\(num)}{\(den)}")
            }
        }
        
        return result
    }

    private static func matchRegex(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        
        var results = [String]()
        results.append(ns.substring(with: match.range(at: 0)))
        for i in 1..<match.numberOfRanges {
            let r = match.range(at: i)
            if r.location != NSNotFound {
                results.append(ns.substring(with: r))
            } else {
                results.append("")
            }
        }
        return results
    }
}

// MARK: - Suggestion Engine (FIM via Ollama)

actor OllamaSuggestionEngine {
    private let runtime: BundledOllamaRuntime
    private let endpoint = URL(string: "http://127.0.0.1:11435/api/generate")!
    private let model = "qwen2.5-coder:0.5b"
    private var lastMessage = "Starting local AI…"
    private var lastFailureTime: ContinuousClock.Instant?
    private let retryCooldown: Duration = .seconds(5)

    init(runtime: BundledOllamaRuntime) {
        self.runtime = runtime
    }

    func statusMessage() -> String { lastMessage }

    func warmup() async {
        lastMessage = "Starting local AI server…"
        do {
            try await runtime.ensureRunning()
            
            lastMessage = "Loading AI model into memory…"
            let prompt = "<|fim_prefix|>// Warmup\n<|fim_suffix|><|fim_middle|>"
            let body = OllamaRequest(
                model: model,
                prompt: prompt,
                raw: true,
                stream: false,
                keepAlive: "30m",
                options: OllamaOptions(
                    temperature: 0.1, topP: 0.9, numPredict: 1, numCtx: 1024, stop: ["\n"]
                )
            )
            
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 30.0 // Needs extra time to load model
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
            
            let _ = try await URLSession.shared.data(for: request)
            
            lastFailureTime = nil
            lastMessage = ""
        } catch is CancellationError {
            return
        } catch {
            print("AI Warmup failed: \(error)")
            lastFailureTime = .now
            lastMessage = "AI Error: \(error.localizedDescription)"
        }
    }

    func suggestLocal(for snapshot: EditorSnapshot) -> SuggestionResult? {
        guard let localResult = LocalMathTranslator.translate(text: snapshot.text) else {
            return nil
        }
        
        let cursor = snapshot.cursorOffset
        let originalText = localResult.original
        
        let rangeToSearch = NSRange(location: max(0, cursor - originalText.count - 20), length: min(cursor, originalText.count + 20))
        if let regex = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: originalText), options: [.caseInsensitive]),
           let match = regex.firstMatch(in: snapshot.text, options: [], range: rangeToSearch) {
            let replaceRange = match.range
            return SuggestionResult(text: localResult.latex, replaceRange: replaceRange)
        } else {
            let startLoc = max(0, cursor - originalText.count)
            let replaceRange = NSRange(location: startLoc, length: cursor - startLoc)
            return SuggestionResult(text: localResult.latex, replaceRange: replaceRange)
        }
    }

    func mightContainMath(_ text: String) -> Bool {
        let nsText = text as NSString
        let maxLen = 150
        let length = nsText.length
        let suffix: String
        if length <= maxLen {
            suffix = text
        } else {
            suffix = nsText.substring(from: length - maxLen)
        }
        
        let mathChars = CharacterSet(charactersIn: "+-*/^=<>()[]{}_\\")
        if suffix.rangeOfCharacter(from: mathChars) != nil {
            return true
        }
        if suffix.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }
        
        let mathKeywords: Set<String> = [
            "squared", "cubed", "power", "plus", "minus", "times", "divide", "over",
            "sum", "product", "integral", "limit", "derivative", "gradient", "divergence",
            "curl", "matrix", "vector", "sqrt", "root", "sin", "cos", "tan", "log", "ln",
            "pi", "theta", "alpha", "beta", "gamma", "delta", "epsilon", "lambda",
            "mu", "sigma", "omega", "phi", "psi", "tau", "rho", "infinity", "equals", "dot", "cross"
        ]
        
        let words = suffix.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        for word in words {
            if mathKeywords.contains(word) {
                return true
            }
        }
        
        return false
    }

    func suggestSlashAI(for snapshot: EditorSnapshot) async -> SuggestionResult? {
        if let lastFailure = lastFailureTime,
           ContinuousClock.now - lastFailure < retryCooldown {
            return nil
        }

        do {
            try await runtime.ensureRunning()
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            lastFailureTime = .now
            lastMessage = error.localizedDescription
            return nil
        }

        let nsText = snapshot.text as NSString
        let cursor = snapshot.cursorOffset
        let prefix = nsText.substring(to: cursor)
        
        // Match the slash command range
        let pattern = "(?:\\s|^)(/[^\\n]*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: prefix, range: NSRange(location: 0, length: prefix.count)) else {
            return nil
        }
        
        let replaceRange = match.range(at: 1)
        let rawMathText = (prefix as NSString).substring(with: NSRange(location: replaceRange.location + 1, length: replaceRange.length - 1))
        let mathText = rawMathText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !mathText.isEmpty else { return nil }

        let prompt = """
Translate math to LaTeX. ONLY raw LaTeX.
Input: pi r squared
Output: \\pi r^2
Input: integral from 0 to infinity of x dx
Output: \\int_{0}^{\\infty} x \\, dx
Input: \(mathText)
Output:
"""

        let body = OllamaRequest(
            model: model,
            prompt: prompt,
            raw: true,
            stream: false,
            keepAlive: "30m",
            options: OllamaOptions(
                temperature: 0.0,
                topP: 0.9,
                numPredict: 40,
                numCtx: 1024,
                stop: ["\n"]
            )
        )

        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:11435/api/generate")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 6.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                lastFailureTime = .now
                lastMessage = "Model not ready — run scripts/vendor-ollama-runtime.sh"
                return nil
            }

            let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
            let rawSuggestion = sanitize(ollamaResponse.response)

            let cleaned = rawSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.uppercased() == "NONE" || cleaned.isEmpty {
                lastMessage = ""
                return nil
            }

            lastFailureTime = nil
            lastMessage = ""

            let latex: String
            if cleaned.hasPrefix("\\(") || cleaned.hasPrefix("\\[") {
                latex = cleaned
            } else {
                latex = "\\( \(cleaned) \\)"
            }

            return SuggestionResult(text: latex, replaceRange: replaceRange)

        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            lastFailureTime = .now
            lastMessage = "AI Error: \(error.localizedDescription)"
            return nil
        }
    }

    func suggestOllama(for snapshot: EditorSnapshot) async -> SuggestionResult? {
        // Don't spam retries during startup — cooldown after failures
        if let lastFailure = lastFailureTime,
           ContinuousClock.now - lastFailure < retryCooldown {
            return nil
        }

        // Ensure the bundled runtime is running and ready
        do {
            try await runtime.ensureRunning()
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            lastFailureTime = .now
            lastMessage = error.localizedDescription
            return nil
        }

        let nsText = snapshot.text as NSString
        let cursor = snapshot.cursorOffset
        let prefixStart = max(0, cursor - 900)
        let rawPrefix = nsText.substring(with: NSRange(location: prefixStart, length: cursor - prefixStart))
        let lines = rawPrefix.components(separatedBy: .newlines)
        let prefix = lines.suffix(3).joined(separator: "\n")
        
        let prompt = """
You are a math-to-LaTeX converter.
If the text ends with math, output exactly: <original>exact math text</original><latex>\\( latex equation \\)</latex>

Input: The area of a circle is pi r squared
Output: <original>pi r squared</original><latex>\\( \\pi r^2 \\)</latex>

Input: and the work w is the integral from 0 to 10 of x squared dx
Output: <original>the integral from 0 to 10 of x squared dx</original><latex>\\( \\int_{0}^{10} x^2 \\, dx \\)</latex>

Input: F=ma
Output: <original>F=ma</original><latex>\\( F = ma \\)</latex>

Input: Ax = lambda x
Output: <original>Ax = lambda x</original><latex>\\( A\\mathbf{x} = \\lambda \\mathbf{x} \\)</latex>

Input: \(prefix)
Output:
"""

        let body = OllamaRequest(
            model: model,
            prompt: prompt,
            raw: true,
            stream: false,
            keepAlive: "30m",
            options: OllamaOptions(
                temperature: 0.0,
                topP: 0.9,
                numPredict: 80,
                numCtx: 2048,
                stop: ["\n"]
            )
        )

        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:11435/api/generate")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 12.0
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                lastFailureTime = .now
                lastMessage = "Model not ready — run scripts/vendor-ollama-runtime.sh"
                return nil
            }

            let ollamaResponse = try JSONDecoder().decode(OllamaResponse.self, from: data)
            let rawSuggestion = sanitize(ollamaResponse.response)

            if rawSuggestion.trimmingCharacters(in: .whitespacesAndNewlines) == "NONE" || rawSuggestion.isEmpty {
                lastMessage = ""
                return nil
            }

            // Success — clear failure state
            lastFailureTime = nil
            lastMessage = ""

            let pattern = "<original>(.*?)</original>\\s*<latex>(.*?)</latex>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: rawSuggestion, range: NSRange(rawSuggestion.startIndex..., in: rawSuggestion)) {
                
                let nsString = rawSuggestion as NSString
                let originalText = nsString.substring(with: match.range(at: 1))
                let latexText = nsString.substring(with: match.range(at: 2))
                
                let cleanedLatex = latexText.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedOriginal = originalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanedOriginal.uppercased() == "NONE" || cleanedLatex.isEmpty
                    || cleanedLatex.contains("\\text{None}") || cleanedLatex.contains("\\text{NONE}")
                    || cleanedLatex == "\\\\( \\\\)" || cleanedLatex == "\\( \\)" {
                    lastMessage = ""
                    return nil
                }
                
                let core = originalText.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).lowercased()
                let nsPrefix = prefix as NSString
                var pIndex = nsPrefix.length - 1
                let coreChars = Array(core)
                var matchStart = -1
                var matchEnd = -1
                
                guard !coreChars.isEmpty else { return nil }
                
                while pIndex >= 0 {
                    let charStr = nsPrefix.substring(with: NSRange(location: pIndex, length: 1))
                    if charStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        pIndex -= 1
                        continue
                    }
                    
                    if charStr.lowercased() == String(coreChars.last!) {
                        var cIndex = coreChars.count - 1
                        var tempPIndex = pIndex
                        
                        while cIndex >= 0 && tempPIndex >= 0 {
                            let tempCharStr = nsPrefix.substring(with: NSRange(location: tempPIndex, length: 1))
                            if tempCharStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                tempPIndex -= 1
                                continue
                            }
                            if tempCharStr.lowercased() == String(coreChars[cIndex]) {
                                cIndex -= 1
                                tempPIndex -= 1
                            } else {
                                break
                            }
                        }
                        
                        if cIndex < 0 {
                            matchStart = tempPIndex + 1
                            matchEnd = pIndex
                            break
                        }
                    }
                    pIndex -= 1
                }
                
                if matchStart != -1 {
                    let absoluteOffset = cursor - nsPrefix.length
                    let replaceRange = NSRange(location: absoluteOffset + matchStart, length: matchEnd - matchStart + 1)
                    return SuggestionResult(text: latexText.trimmingCharacters(in: .whitespacesAndNewlines), replaceRange: replaceRange)
                }
                
                return nil
            }
            return nil

        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            lastFailureTime = .now
            lastMessage = "AI Error: \(error.localizedDescription)"
            return nil
        }
    }

    private func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{0000}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Bundled Ollama Runtime

actor BundledOllamaRuntime {
    private var process: Process?
    private var isReady = false

    func ensureRunning() async throws {
        if isReady { return }
        
        let healthURL = URL(string: "http://127.0.0.1:11435/api/tags")!
        
        // Fast-path: check if it's already running (either by us, or an orphaned process)
        var fastReq = URLRequest(url: healthURL)
        fastReq.timeoutInterval = 3.0
        if let (_, response) = try? await URLSession.shared.data(for: fastReq),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            isReady = true
            return
        }

        isReady = false

        // Start the process if it's not running
        if process == nil || !(process?.isRunning ?? false) {
            // Force kill any existing zombie ollama runners to avoid CPU saturation and free GPU
            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            killTask.arguments = ["-f", "ollama"]
            try? killTask.run()
            killTask.waitUntilExit()

            guard let ollamaURL = Bundle.main.url(
                forResource: "ollama",
                withExtension: nil,
                subdirectory: "Ollama"
            ) else {
                throw RuntimeError(
                    "Bundled Ollama runtime not found. "
                    + "Run scripts/vendor-ollama-runtime.sh first."
                )
            }

            guard let modelsURL = Bundle.main.resourceURL?
                .appendingPathComponent("OllamaModels", isDirectory: true) else {
                throw RuntimeError("Bundled AI model directory is missing.")
            }

            let wrapperScript = """
            #!/bin/bash
            "\(ollamaURL.path)" serve &
            PID=$!
            while kill -0 $PPID 2>/dev/null; do
                sleep 1
            done
            kill -9 $PID
            """
            let scriptPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ollama-wrapper.sh")
            try? wrapperScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

            let launched = Process()
            launched.executableURL = scriptPath
            launched.arguments = []
            
            var env = ProcessInfo.processInfo.environment
            env["OLLAMA_HOST"] = "127.0.0.1:11435"
            env["OLLAMA_MODELS"] = modelsURL.path
            env["OLLAMA_KEEP_ALIVE"] = "30m"
            launched.environment = env

            let logPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tabnote-ollama.log")
            FileManager.default.createFile(atPath: logPath.path, contents: nil, attributes: nil)
            if let fh = try? FileHandle(forWritingTo: logPath) {
                launched.standardOutput = fh
                launched.standardError = fh
            }

            do {
                try launched.run()
                process = launched
            } catch {
                throw RuntimeError("Could not start bundled local AI runtime.")
            }
        }

        // Poll until the API is responsive (up to 15 seconds)
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { throw CancellationError() }
            do {
                var healthReq = URLRequest(url: healthURL)
                healthReq.timeoutInterval = 3.0
                let (_, response) = try await URLSession.shared.data(for: healthReq)
                if let http = response as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode) {
                    isReady = true
                    return
                }
            } catch {
                continue
            }
        }

        throw RuntimeError("Local AI server did not start within 15 seconds.")
    }
}

// MARK: - Data Models

struct EditorSnapshot: Sendable {
    let text: String
    let cursorOffset: Int
}

struct SuggestionResult: Sendable {
    let text: String
    let replaceRange: NSRange?
}

struct OllamaRequest: Encodable {
    let model: String
    let prompt: String
    let raw: Bool
    let stream: Bool
    let keepAlive: String
    let options: OllamaOptions

    enum CodingKeys: String, CodingKey {
        case model, prompt, raw, stream
        case keepAlive = "keep_alive"
        case options
    }
}

struct OllamaOptions: Encodable {
    let temperature: Double
    let topP: Double
    let numPredict: Int
    let numCtx: Int
    let stop: [String]

    enum CodingKeys: String, CodingKey {
        case temperature
        case topP = "top_p"
        case numPredict = "num_predict"
        case numCtx = "num_ctx"
        case stop
    }
}

struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let raw: Bool
    let stream: Bool
    let keepAlive: String
    let options: OllamaOptions

    enum CodingKeys: String, CodingKey {
        case model, prompt, raw, stream
        case keepAlive = "keep_alive"
        case options
    }
}

struct OllamaChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let keepAlive: String
    let options: OllamaOptions

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case keepAlive = "keep_alive"
        case options
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatResponse: Decodable {
    let message: ChatMessage
}

struct OllamaResponse: Decodable {
    let response: String
}

struct RuntimeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

@MainActor
func createTabKeyImage(font: NSFont) -> NSImage {
    let text = "⇥ Tab"
    let buttonFont = NSFont.systemFont(ofSize: font.pointSize * 0.70, weight: .medium)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: buttonFont,
        .foregroundColor: NSColor.secondaryLabelColor
    ]
    let size = text.size(withAttributes: attributes)
    let padding = CGSize(width: 8, height: 3)
    let rect = CGRect(origin: .zero, size: CGSize(width: size.width + padding.width * 2, height: size.height + padding.height * 2))
    
    let image = NSImage(size: rect.size)
    image.lockFocus()
    
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
    NSColor.labelColor.withAlphaComponent(0.06).setFill()
    path.fill()
    NSColor.labelColor.withAlphaComponent(0.12).setStroke()
    path.lineWidth = 1.0
    path.stroke()
    
    text.draw(at: CGPoint(x: padding.width, y: padding.height), withAttributes: attributes)
    
    image.unlockFocus()
    return image
}
