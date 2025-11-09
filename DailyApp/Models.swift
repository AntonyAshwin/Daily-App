//
//  Models.swift
//  DailyApp
//
//  Created by Assistant on 12/10/25.
//

import Foundation
import SwiftData

// Schema versioning for proper migration
enum TaskSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [TaskEntry.self]
    }
    
    @Model
    final class TaskEntry: Identifiable {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var isCompleted: Bool
        var position: Double
        
        init(title: String, createdAt: Date = Date(), isCompleted: Bool = false, position: Double = 0) {
            self.id = UUID()
            self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.createdAt = createdAt
            self.isCompleted = isCompleted
            self.position = position
        }
    }
}

enum TaskSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [TaskEntry.self]
    }
    
    @Model
    final class TaskEntry: Identifiable {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var isCompleted: Bool
        var position: Double
        var isDaily: Bool // Added in v2
        
        init(title: String, createdAt: Date = Date(), isCompleted: Bool = false, position: Double = 0, isDaily: Bool = false) {
            self.id = UUID()
            self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            self.createdAt = createdAt
            self.isCompleted = isCompleted
            self.position = position
            self.isDaily = isDaily
        }
    }
}

// Use the current version
typealias TaskEntry = TaskSchemaV2.TaskEntry

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
    
    // NEW: Find daily tasks that need to be created for a specific day
    static func dailyTasksNeedingCreation(for day: Date, in tasks: [TaskEntry]) -> [TaskEntry] {
        let cal = Calendar.current
        // Group all tasks by title (include past days)
        let grouped = Dictionary(grouping: tasks) { $0.title }
        var tasksToCreate: [TaskEntry] = []
        for (_, entries) in grouped {
            guard let latest = entries.max(by: { $0.createdAt < $1.createdAt }) else { continue }
            // Only consider if the latest instance is still marked daily
            guard latest.isDaily else { continue }
            // Skip if a task (daily or not) already exists for target day with same title
            let existsForDay = entries.contains { cal.isDate($0.createdAt, inSameDayAs: day) }
            if !existsForDay {
                tasksToCreate.append(latest)
            }
        }
        return tasksToCreate
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
