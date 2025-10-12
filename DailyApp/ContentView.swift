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
    // If filtering in memory fails for some reason, you can switch to a predicate-based query like:
    // @Query(filter: #Predicate<TaskEntry> { Calendar.current.isDateInToday($0.createdAt) }, sort: \\TaskEntry.createdAt) private var todaysQueryTasks: [TaskEntry]

    @State private var showingAddSheet = false
    @State private var rawInput: String = ""
    @State private var now: Date = Date()

    private var todaysTasks: [TaskEntry] {
        TaskEntry.tasks(for: now, in: allTasks)
        // Or if using predicate version above: todaysQueryTasks
    }

    private var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .full
        return df
    }()

    var body: some View {
        NavigationStack {
            Group {
                if todaysTasks.isEmpty {
                    ContentUnavailableView("No Tasks Yet", systemImage: "calendar", description: Text("Add your tasks for today using the + button."))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(todaysTasks) { task in
                                TaskCardView(task: task)
                                    .onTapGesture { toggle(task) }
                                    .animation(.spring(), value: task.isCompleted)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle(dateFormatter.string(from: now))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(destination: HistoryView()) { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("History")
                }
                ToolbarItem(placement: .primaryAction) {
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
        print("[CreateTasks] Parsed titles: \(titles)")
        titles.forEach { title in
            let entry = TaskEntry(title: title, createdAt: creationDate)
            context.insert(entry)
            print("[CreateTasks] Inserted task: \(entry.title) at \(entry.createdAt)")
        }
        do { try context.save(); print("[CreateTasks] Context save success") } catch { print("[CreateTasks] Save error: \(error)") }
        showingAddSheet = false
        rawInput = ""
        now = Date() // ensure today's date is current
        // Force a refresh check
        refreshDateIfNeeded()
    }

    private func toggle(_ task: TaskEntry) {
        task.isCompleted.toggle()
        do { try context.save() } catch { print("Toggle save error: \(error)") }
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
