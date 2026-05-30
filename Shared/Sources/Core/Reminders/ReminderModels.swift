import Foundation

public enum VoiceIntent: String, CaseIterable, Codable, Sendable, Equatable {
    case dictation
    case reminder
}

public struct ReminderDueDate: Codable, Sendable, Equatable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int?
    public let minute: Int?

    public init(year: Int, month: Int, day: Int, hour: Int? = nil, minute: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    public var dateComponents: DateComponents {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        return c
    }
}

public struct CreatedReminder: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let listName: String
    public let dueDate: ReminderDueDate?
    public let createdAt: Date

    public init(
        id: String,
        title: String,
        listName: String,
        dueDate: ReminderDueDate? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.listName = listName
        self.dueDate = dueDate
        self.createdAt = createdAt
    }
}

public struct ReminderListInfo: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public var isDefault: Bool

    public init(id: String, name: String, isDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
    }
}

public struct ReminderSnapshot: Codable, Sendable, Equatable {
    public let lists: [ReminderListInfo]
    public let recentReminders: [CreatedReminder]
    public let updatedAt: Date

    public init(
        lists: [ReminderListInfo] = [],
        recentReminders: [CreatedReminder] = [],
        updatedAt: Date = Date()
    ) {
        self.lists = lists
        self.recentReminders = recentReminders
        self.updatedAt = updatedAt
    }
}
