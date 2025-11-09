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
    @State private var editIsDaily: Bool = false // NEW: for editing daily status
    @State private var quickEntryText: String = ""
    @FocusState private var quickEntryFocused: Bool

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
    
    private var completionProgress: Double {
        guard !todaysTasks.isEmpty else { return 0 }
        let completed = todaysTasks.filter { $0.isCompleted }.count
        return Double(completed) / Double(todaysTasks.count)
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
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        List {
                            if !todaysTasks.isEmpty {
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
                            
                            // Quick entry card at bottom
                            QuickEntryCardView(text: $quickEntryText, isFocused: $quickEntryFocused, onCreate: quickCreateTask)
                                .id("quickEntry")
                            
                            // Add extra tappable space when keyboard is focused for easy dismissal
                            if quickEntryFocused {
                                Color.clear
                                    .frame(height: 200)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        quickEntryFocused = false
                                    }
                                    .listRowSeparator(.hidden)
                                    .id("spacer")
                            }
                        }
                        .listStyle(.plain)
                        .onChange(of: quickEntryFocused) { _, isFocused in
                            if isFocused {
                                // Use a longer delay and scroll to the text field itself first
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeInOut(duration: 0.6)) {
                                        proxy.scrollTo("quickEntry", anchor: .center)
                                    }
                                    // Then scroll to spacer if it exists
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            proxy.scrollTo("spacer", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    // Fixed progress bar at bottom (only show if tasks exist and keyboard not focused)
                    if !todaysTasks.isEmpty && !quickEntryFocused {
                        ProgressBarView(progress: completionProgress)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                    }
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
                    
                    Button { quickEntryFocused = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel("Add Quick Task")
                    
                    Button { showingAddSheet = true } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16))
                    }
                    .accessibilityLabel("Bulk Add Tasks")
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
            .onAppear { 
                refreshDateIfNeeded()
                createDailyTasksIfNeeded() // NEW: Auto-create daily tasks
            }
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
                    Section("Repeat") {
                        Toggle("Daily Task", isOn: $editIsDaily)
                        if editIsDaily {
                            Text("This task will automatically be created every day")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        editIsDaily = task.isDaily // NEW: Set daily status
    }

    private func saveEdit() {
        guard let task = editingTask else { return }
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let oldTitle = task.title
        task.title = trimmed
        task.isDaily = editIsDaily

        // If Daily turned off, propagate to prior tasks with same title to prevent resurrection
        if !editIsDaily {
            for t in allTasks where t.title == oldTitle {
                t.isDaily = false
            }
        }

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

    // NEW: Create daily tasks for today if they don't exist
    private func createDailyTasksIfNeeded() {
        let tasksToCreate = TaskEntry.dailyTasksNeedingCreation(for: now, in: allTasks)
        
        guard !tasksToCreate.isEmpty else { return }
        
        let currentPositions = todaysTasks.map { $0.position }
        var nextPos = (currentPositions.max() ?? 0) + 1
        
        for template in tasksToCreate {
            // Create new task based on template but for today
            let cal = Calendar.current
            let timeParts = cal.dateComponents([.hour, .minute, .second], from: template.createdAt)
            var todayParts = cal.dateComponents([.year, .month, .day], from: now)
            todayParts.hour = timeParts.hour
            todayParts.minute = timeParts.minute
            todayParts.second = timeParts.second
            
            let todayDate = cal.date(from: todayParts) ?? now
            
            let newTask = TaskEntry(
                title: template.title,
                createdAt: todayDate,
                isCompleted: false,
                position: nextPos,
                isDaily: true
            )
            
            context.insert(newTask)
            nextPos += 1
        }
        
        do { 
            try context.save() 
        } catch { 
            print("Daily task creation error: \(error)") 
        }
    }

    private func refreshDateIfNeeded() {
        // If app stayed open over midnight, refresh displayed day
        let cal = Calendar.current
        if !cal.isDate(now, inSameDayAs: Date()) {
            now = Date()
            createDailyTasksIfNeeded() // Create daily tasks for new day
        }
    }

    private func quickCreateTask() {
        let trimmed = quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let creationDate = Date()
        let currentPositions = todaysTasks.map { $0.position }
        let nextPos = (currentPositions.max() ?? 0) + 1
        
        let entry = TaskEntry(title: trimmed, createdAt: creationDate, position: nextPos)
        context.insert(entry)
        
        // Clear text first, before save
        quickEntryText = ""
        
        do { 
            try context.save() 
        } catch { 
            print("Quick create save error: \(error)") 
        }
        
        // Restore focus after a brief delay to ensure the view update completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            quickEntryFocused = true
        }
    }
}

struct ProgressBarView: View {
    let progress: Double
    @State private var animatedProgress: Double = 0
    
    private var progressColor: Color {
        // Interpolate from light red to light green
        let red = Color.red.opacity(0.3)
        let green = Color.green.opacity(0.3)
        return Color(
            red: (1 - progress) * 0.8 + progress * 0.2,
            green: progress * 0.8 + (1 - progress) * 0.2,
            blue: 0.2
        )
    }
    
    private var motivationalPhrase: String {
        let percentage = Int(progress * 100)
        switch percentage {
        case 0: return "Let's get started!"
        case 1...5: return "First step taken!"
        case 6...10: return "Building momentum"
        case 11...20: return "Getting warmed up"
        case 21...30: return "Making progress"
        case 31...40: return "Keep it rolling"
        case 41...50: return "Halfway there!"
        case 51...60: return "Over the hump"
        case 61...70: return "Strong momentum"
        case 71...75: return "Almost there"
        case 76...80: return "On the home stretch"
        case 81...85: return "So close now"
        case 86...90: return "Final push"
        case 91...95: return "Almost perfect"
        case 96...99: return "One more to go"
        case 100: return "All done! 🎉"
        default: return "Keep going"
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(motivationalPhrase)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                    .animation(.easeInOut(duration: 0.3), value: motivationalPhrase)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 20)
                    
                    // Progress fill with animation
                    RoundedRectangle(cornerRadius: 12)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * animatedProgress, height: 20)
                        .animation(.easeInOut(duration: 0.8), value: animatedProgress)
                    
                    // Shimmer effect when completing
                    if animatedProgress > 0.9 {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.6), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 40, height: 20)
                            .offset(x: animatedProgress > 0.99 ? geometry.size.width : -40)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: animatedProgress > 0.99)
                    }
                }
            }
            .frame(height: 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedProgress = newValue
            }
        }
    }
}

struct QuickEntryCardView: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onCreate: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .foregroundStyle(.gray)
                .font(.title3)
                .padding(.top, 2)
            
            TextField("Add new task...", text: $text)
                .font(.headline)
                .focused($isFocused)
                .onSubmit {
                    onCreate()
                }
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
            
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.1), in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
        .contentShape(.rect)
        .onTapGesture {
            isFocused = true
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
                HStack {
                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.isCompleted, pattern: .solid, color: .primary.opacity(0.6))
                    if task.isDaily {
                        Image(systemName: "repeat")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
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
