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
                    ForEach(links, id: \.objectID) { link in
                        linkRow(link)
                    }
                    .onDelete(perform: deleteLinks)
                }

                Button {
                    showingAddReminders = true
                } label: {
                    Label("Add Reminders", systemImage: "plus")
                }
            }
            
#if DEBUG
Section("Developer") {
    DebugHabitToolsSection(habit: habit)
}
#endif
        }
        .navigationTitle(habit.name ?? "Habit")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddReminders) {
            AddRemindersSheet(habit: habit)
                .environment(\.managedObjectContext, context)
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func linkRow(_ link: HabitReminderLink) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(for: link))
                    .lineLimit(1)

                Text(link.isRequired ? "Required" : "Optional")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { link.isRequired },
                set: { newValue in
                    link.isRequired = newValue
                    saveContext()
                }
            ))
            .labelsHidden()
        }
    }

    private func displayTitle(for link: HabitReminderLink) -> String {
        let t = (link.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return "Reminder"
    }

    // MARK: - Delete

    private func deleteLinks(at offsets: IndexSet) {
        let currentLinks = links
        for index in offsets {
            context.delete(currentLinks[index])
        }
        saveContext()
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("❌ HabitDetailView: failed saving context: \(error)")
        }
    }
}
