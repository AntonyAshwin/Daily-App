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
        let dailyTasks = tasks.filter { $0.isDaily }
        
        // Group by title to find unique daily tasks
        let dailyTasksByTitle = Dictionary(grouping: dailyTasks) { $0.title }
        
        var tasksToCreate: [TaskEntry] = []
        
        for (title, titleTasks) in dailyTasksByTitle {
            // Check if this daily task already exists for the target day
            let existsForDay = titleTasks.contains { cal.isDate($0.createdAt, inSameDayAs: day) }
            
            if !existsForDay {
                // Find the most recent version of this daily task to use as template
                if let template = titleTasks.max(by: { $0.createdAt < $1.createdAt }) {
                    tasksToCreate.append(template)
                }
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
