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
    var position: Double // ordering index (allows inserting between if needed)

    init(title: String, createdAt: Date = Date(), isCompleted: Bool = false, position: Double = 0) {
        self.id = UUID()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.isCompleted = isCompleted
        self.position = position
    }
}

extension TaskEntry {
    /// Assign missing position values (migration helper when adding the field later)
    static func backfillPositions(_ tasks: [TaskEntry]) {
        var counter = 1.0
        for t in tasks.sorted(by: { $0.createdAt < $1.createdAt }) where t.position == 0 {
            t.position = counter
            counter += 1
        }
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
