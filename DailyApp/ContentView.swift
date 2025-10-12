//
//  ContentView.swift
//  DailyApp
//
//  Created by Ashwin, Antony on 12/10/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskEntry.createdAt, order: .forward) private var allTasks: [TaskEntry]
    @Environment(\.editMode) private var editMode

    @State private var showingAddSheet = false
    @State private var rawInput: String = ""
    @State private var now: Date = Date()

    private var todaysTasks: [TaskEntry] {
        // Single source of truth: always ordered purely by position.
        // Grouping is only applied when user taps Sort (which rewrites positions).
        return TaskEntry.tasks(for: now, in: allTasks)
            .sorted { $0.position < $1.position }
    }

    private var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        // Shorter header format (e.g. "Sun, 12 Oct") to avoid long large titles
        df.setLocalizedDateFormatFromTemplate("E, d MMM")
        return df
    }()

    var body: some View {
        NavigationStack {
            Group {
                if todaysTasks.isEmpty {
                    ContentUnavailableView("No Tasks Yet", systemImage: "calendar", description: Text("Add your tasks for today using the + button."))
                } else {
                    List {
                        ForEach(todaysTasks) { task in
                            TaskCardView(task: task)
                                .onTapGesture { toggle(task) }
                        }
                        .onMove(perform: move)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(dateFormatter.string(from: now))
            .navigationBarTitleDisplayMode(.inline) // use compact inline style
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: HistoryView()) { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("History")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { sortGroupIncompleteFirst() } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(.title2)
                    }
                    .accessibilityLabel("Group Incomplete First")
                    Button { showingAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.title2)
                    }
                    .accessibilityLabel("Add Tasks")
                }
            }
            .sheet(isPresented: $showingAddSheet, onDismiss: { rawInput = "" }) {
                NavigationStack {
                    Form {
                        Section("Daily Tasks (comma separated)") {
                            TextEditor(text: $rawInput)
                                .frame(minHeight: 120)
                                .font(.body.monospaced())
                                .overlay(alignment: .topLeading) {
                                    if rawInput.isEmpty { Text("e.g. Workout, Read book, Meditate").foregroundStyle(.secondary).padding(.top, 8) }
                                }
                        }
                        if !parsedInput.isEmpty {
                            Section("Preview (\(parsedInput.count))") {
                                ForEach(parsedInput, id: \.self) { t in Text(t) }
                            }
                        }
                    }
                    .navigationTitle("Add Tasks")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingAddSheet = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("Create") { createTasks() }.disabled(parsedInput.isEmpty) }
                    }
                }
            }
            .onAppear { refreshDateIfNeeded() }
        }
    }

    private var parsedInput: [String] { TaskInputParser.parse(rawInput) }

    private func createTasks() {
        let titles = parsedInput
        guard !titles.isEmpty else { return }
        let creationDate = Date()
        // Determine current max position among today's tasks
        let currentPositions = todaysTasks.map { $0.position }
        var nextPos = (currentPositions.max() ?? 0) + 1
        titles.forEach { title in
            let entry = TaskEntry(title: title, createdAt: creationDate, position: nextPos)
            context.insert(entry)
            nextPos += 1
        }
        do { try context.save() } catch { print("Save error: \(error)") }
        showingAddSheet = false
        rawInput = ""
        now = Date() // ensure today's date is current
        refreshDateIfNeeded()
    }

    private func toggle(_ task: TaskEntry) {
        task.isCompleted.toggle()
        // No automatic positional jump; user decides when to regroup via Sort button.
        do { try context.save() } catch { print("Toggle save error: \(error)") }
    }

    private func move(from source: IndexSet, to destination: Int) {
        // Work on a mutable copy of current order (already sorted with incomplete first)
        var ordered = todaysTasks.sorted { $0.position < $1.position } // ensure raw positional order for adjustment
        ordered.move(fromOffsets: source, toOffset: destination)
        // Reassign positions sequentially (keep incomplete/complete grouping implicit by order user sees)
        for (idx, task) in ordered.enumerated() {
            task.position = Double(idx + 1)
        }
        do { try context.save() } catch { print("Reorder save error: \(error)") }
    }

    private func sortGroupIncompleteFirst() {
        // Reassign positions so incomplete tasks (preserving relative order) are first.
        let incompletes = todaysTasks.filter { !$0.isCompleted }
        let completes = todaysTasks.filter { $0.isCompleted }
        var counter = 1.0
        for t in incompletes { t.position = counter; counter += 1 }
        for t in completes { t.position = counter; counter += 1 }
        do { try context.save() } catch { print("Sort save error: \(error)") }
    }

    private func refreshDateIfNeeded() {
        // If app stayed open over midnight, refresh displayed day
        let cal = Calendar.current
        if !cal.isDate(now, inSameDayAs: Date()) {
            now = Date()
        }
    }
}

struct TaskCardView: View {
    @Environment(\.modelContext) private var context
    @Bindable var task: TaskEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.isCompleted ? .green : .red)
                .font(.title3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.headline)
                    .strikethrough(task.isCompleted, pattern: .solid, color: .primary.opacity(0.6))
                Text(task.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(task.isCompleted ? Color.green.opacity(0.25) : Color.red.opacity(0.25), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Task: \(task.title)")
        .accessibilityHint(task.isCompleted ? "Completed" : "Incomplete")
    }
}

#Preview {
    ContentView()
}
