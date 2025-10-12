//
//  Models.swift
//  DailyApp
//
//  Created by Assistant on 12/10/25.
//

import Foundation
import SwiftData

@Model
final class TaskEntry: Identifiable {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var isCompleted: Bool

    init(title: String, createdAt: Date = Date(), isCompleted: Bool = false) {
        self.id = UUID()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.isCompleted = isCompleted
    }
}

extension TaskEntry {
    static func tasks(for day: Date, in tasks: [TaskEntry]) -> [TaskEntry] {
        let cal = Calendar.current
        return tasks.filter { cal.isDate($0.createdAt, inSameDayAs: day) }
            .sorted { $0.createdAt < $1.createdAt }
    }
}

enum TaskInputParser {
    static func parse(_ raw: String) -> [String] {
        // Support commas, newlines, semicolons as delimiters
        let delimiters = CharacterSet(charactersIn: ",;\n")
        return raw
            .components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
