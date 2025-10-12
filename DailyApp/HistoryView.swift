//
//  HistoryView.swift
//  DailyApp
//
//  Created by Assistant on 12/10/25.
//

import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \TaskEntry.createdAt, order: .reverse) private var tasks: [TaskEntry]
    @State private var grouped: [(date: Date, tasks: [TaskEntry])] = []

    var body: some View {
        List {
            if grouped.isEmpty {
                ContentUnavailableView("No History", systemImage: "clock", description: Text("You'll see past days here."))
            } else {
                ForEach(grouped, id: \.date) { group in
                    Section(header: Text(group.date, formatter: dateFormatter)) {
                        ForEach(group.tasks) { task in
                            HStack {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isCompleted ? .green : .red)
                                Text(task.title)
                                Spacer()
                                Text(task.createdAt, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .listRowBackground(task.isCompleted ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .onAppear(perform: buildGroups)
        .onChange(of: tasks) { _ in buildGroups() }
    }

    private func buildGroups() {
        let cal = Calendar.current
        let dict = Dictionary(grouping: tasks) { task in
            cal.startOfDay(for: task.createdAt)
        }
        grouped = dict.map { ($0.key, $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { $0.date > $1.date }
            .filter { !cal.isDateInToday($0.date) } // Exclude today (shown on main screen)
    }

    private var dateFormatter: DateFormatter { let df = DateFormatter(); df.dateStyle = .medium; return df }
}

#Preview {
    NavigationStack { HistoryView() }
}
