import Foundation

/// A single todo. Value type, persisted as JSON.
///
/// `day` is the grouping key: a date normalized to local start-of-day. The panel shows
/// all items whose `day` matches the selected day, ordered by `sortOrder`.
public struct TodoItem: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var isCompleted: Bool
    /// Start-of-day (local) bucket this todo belongs to.
    public var day: Date
    /// Rank within its day. Lower sorts first. Renumbered on reorder.
    public var sortOrder: Double
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        day: Date,
        sortOrder: Double,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.day = day
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}
