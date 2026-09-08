import Foundation

struct GlyphNote: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var contentPreview: String
    var lastModified: Date
    var richTextData: Data

    /// The course this note belongs to. `nil` means unfiled.
    ///
    /// Coursework is organised by subject, not by the day it happened — "MATH 51",
    /// not "Previous 7 Days". Notes are grouped the way a student already thinks.
    var course: String?

    /// Lowercased plain text of the note with every equation expanded to its LaTeX,
    /// so searching for "integral" or "sqrt" finds the equation itself.
    ///
    /// Written at save time. Notes saved before this existed decode it as `nil` and
    /// fall back to title matching until their next save.
    var searchText: String?

    /// When the note was moved to Recently Deleted. `nil` for a live note.
    ///
    /// Deletion is a keystroke away and a term of lecture notes is not something to
    /// destroy on a mistyped shortcut, so the file stays on disk until the writer
    /// says otherwise.
    var deletedAt: Date?

    var isDeleted: Bool { deletedAt != nil }

    static func == (lhs: GlyphNote, rhs: GlyphNote) -> Bool {
        lhs.id == rhs.id
    }

    /// True when the note matches a lowercased query.
    func matches(_ query: String) -> Bool {
        if title.lowercased().contains(query) { return true }
        if let course, course.lowercased().contains(query) { return true }
        if let searchText { return searchText.contains(query) }
        return contentPreview.lowercased().contains(query)
    }
}
