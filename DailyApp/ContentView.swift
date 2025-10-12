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
    // Fetch all tasks sorted by position so manual ordering persists without jitter
    @Query(sort: \TaskEntry.position, order: .forward) private var allTasks: [TaskEntry]
    // Removed edit mode / manual reordering

    @State private var showingAddSheet = false
    @State private var rawInput: String = ""
    @State private var now: Date = Date()
    @State private var completedFirst: Bool = false // false = incomplete first
    // Removed forceEditMode (no manual drag reorder)
    @State private var lastDeleted: DeletedSnapshot? = nil
    @State private var showUndoBar: Bool = false
    @State private var undoTimer: Timer? = nil
    @State private var editingTask: TaskEntry? = nil
    @State private var editTitle: String = ""
    @State private var editTime: Date = Date()

    private struct DeletedSnapshot {
        let id: UUID
        let title: String
        let createdAt: Date
        let isCompleted: Bool
        let formerPosition: Double
    }

    private var todaysTasks: [TaskEntry] {
        let base = TaskEntry.tasks(for: now, in: allTasks)
        let incompletes = base.filter { !$0.isCompleted }
        let completes = base.filter { $0.isCompleted }
        return completedFirst ? (completes + incompletes) : (incompletes + completes)
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) { deleteTask(task) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { beginEdit(task) } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }.tint(.blue)
                                }
                        }
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
                    Button { completedFirst.toggle(); normalizePositionsStable() } label: {
                        Image(systemName: completedFirst ? "arrow.down" : "arrow.up")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel(completedFirst ? "Completed first" : "Incomplete first")
                    Button { showingAddSheet = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16))
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
        .overlay(alignment: .bottom) {
            if showUndoBar, let snap = lastDeleted {
                HStack(spacing: 12) {
                    Text("Deleted \(snap.title)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .font(.subheadline)
                    Spacer()
                    Button("Undo") { undoDelete() }
                        .font(.subheadline.bold())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: .capsule)
                .shadow(radius: 4)
                .padding(.bottom, 20)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    // Reordering disabled: no editMode environment
        .sheet(item: $editingTask, onDismiss: { editingTask = nil }) { task in
            NavigationStack {
                Form {
                    Section("Title") {
                        TextField("Title", text: $editTitle)
                            .textInputAutocapitalization(.sentences)
                    }
                    Section("Time") {
                        DatePicker("Time", selection: $editTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                    }
                }
                .navigationTitle("Edit Task")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingTask = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveEdit() }
                            .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
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
        let wasCompleted = task.isCompleted
        task.isCompleted.toggle()
        if wasCompleted != task.isCompleted {
            // Put toggled task at end of its new group
            let siblings = TaskEntry.tasks(for: now, in: allTasks).filter { $0.isCompleted == task.isCompleted && $0.id != task.id }
            let maxPos = siblings.map { $0.position }.max() ?? 0
            task.position = maxPos + 1
            normalizePositionsStable()
        }
        do { try context.save() } catch { print("Toggle save error: \(error)") }
    }


    private func normalizePositionsStable() {
        // Normalize across current visual order to keep positions tight
        var counter = 1.0
        for t in todaysTasks { t.position = counter; counter += 1 }
    }

    private func deleteTask(_ task: TaskEntry) {
        // Capture snapshot
        lastDeleted = DeletedSnapshot(id: task.id, title: task.title, createdAt: task.createdAt, isCompleted: task.isCompleted, formerPosition: task.position)
        context.delete(task)
        normalizePositionsStable()
        do { try context.save() } catch { print("Delete save error: \\(error)") }
        presentUndoBar()
    }

    private func presentUndoBar() {
        undoTimer?.invalidate()
        withAnimation { showUndoBar = true }
        // Auto dismiss after 5 seconds
        undoTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { _ in
            withAnimation { showUndoBar = false }
            lastDeleted = nil
        }
    }

    private func undoDelete() {
        guard let snap = lastDeleted else { return }
        // Recreate entry only if still same day to avoid reviving past history incorrectly
    let entry = TaskEntry(title: snap.title, createdAt: snap.createdAt, isCompleted: snap.isCompleted, position: snap.formerPosition)
        context.insert(entry)
        normalizePositionsStable()
        do { try context.save() } catch { print("Undo save error: \(error)") }
        undoTimer?.invalidate()
        withAnimation { showUndoBar = false }
        lastDeleted = nil
    }

    private func beginEdit(_ task: TaskEntry) {
        editingTask = task
        editTitle = task.title
        editTime = task.createdAt
    }

    private func saveEdit() {
        guard let task = editingTask else { return }
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        task.title = trimmed
        // Keep date component same, adjust time
        let cal = Calendar.current
        var dateParts = cal.dateComponents([.year, .month, .day], from: task.createdAt)
        let timeParts = cal.dateComponents([.hour, .minute, .second], from: editTime)
        dateParts.hour = timeParts.hour
        dateParts.minute = timeParts.minute
        dateParts.second = timeParts.second
        if let newDate = cal.date(from: dateParts) { task.createdAt = newDate }
        do { try context.save() } catch { print("Edit save error: \(error)") }
        editingTask = nil
    }

    // Removed manual ordering & persistence: only two alphabetical group states remain.

    // Removed manual drag/complex multi-state sort; simple toggle only.

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
