import AppKit

func test(tv: NSTextView) {
    if #available(macOS 14.0, *) {
        tv.inlinePredictionType = .no
    }
}
