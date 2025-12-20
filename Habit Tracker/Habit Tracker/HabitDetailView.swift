//
//  HabitDetailView.swift
//  Habit Tracker
//
//  Created by John Fuller on 12/20/25.
//


import SwiftUI
import CoreData

struct HabitDetailView: View {
    @ObservedObject var habit: Habit
    @Environment(\.managedObjectContext) private var context

    @State private var showingAddReminders = false

    private var links: [HabitReminderLink] {
        let set = (habit.reminderLinks as? Set<HabitReminderLink>) ?? []
        return set.sorted { ($0.title ?? "") < ($1.title ?? "") }
    }

    var body: some View {
        List {
            Section("Linked Reminders") {
                if links.isEmpty {
                    Text("No reminders linked yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(links, id: \.id) { link in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.title ?? "(Untitled)")
                                    .lineLimit(1)

                                Text(link.isRequired ? "Required" : "Optional")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .onDelete(perform: deleteLinks)
                }

                Button {
                    showingAddReminders = true
                } label: {
                    Label("Add Reminders", systemImage: "plus")
                }
            }
        }
        .navigationTitle(habit.name ?? "Habit")
        .sheet(isPresented: $showingAddReminders) {
            AddRemindersSheet(habit: habit)
                .environment(\.managedObjectContext, context)
        }
    }

    private func deleteLinks(at offsets: IndexSet) {
        for index in offsets {
            context.delete(links[index])
        }
        do {
            try context.save()
        } catch {
            print("Failed deleting links: \(error)")
        }
    }
}