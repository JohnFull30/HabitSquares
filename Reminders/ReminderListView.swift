import SwiftUI
import CoreData
import EventKit

struct ReminderListView: View {
    // MARK: - Environment
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    /// The habit we are linking reminders to
    @ObservedObject var habit: Habit
    
    // MARK: - State
    
    @State private var reminders: [EKReminder] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    /// Currently selected Reminders list ("All Lists" shows everything)
    @State private var selectedListName: String = "All Lists"
    private let allListsOption = "All Lists"
    
    /// Identifiers of reminders already linked to this habit
    @State private var linkedReminderIDs: Set<String> = []
    
    // MARK: - Derived data
    
    /// All list names present in today's reminders (sorted)
    private var listNames: [String] {
        let titles = reminders.compactMap { $0.calendar?.title }
        let unique = Set(titles)
        return Array(unique)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    /// Reminders filtered by selected list
    private var filteredReminders: [EKReminder] {
        if selectedListName == allListsOption {
            return reminders
        } else {
            return reminders.filter { $0.calendar?.title == selectedListName }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // List picker
                if !listNames.isEmpty {
                    Picker("List", selection: $selectedListName) {
                        Text(allListsOption).tag(allListsOption)
                        ForEach(listNames, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding([.top, .horizontal])
                }
                
                List {
                    if isLoading {
                        ProgressView("Loading reminders…")
                    } else if let message = errorMessage {
                        Text(message)
                            .foregroundStyle(.red)
                    } else if filteredReminders.isEmpty {
                        Text("No reminders due today in this list.")
                            .foregroundStyle(.secondary)
                    } else {
                        Section(header: Text("Tap to link to \"\(habit.name ?? "Habit")\"")) {
                            ForEach(filteredReminders, id: \.calendarItemIdentifier) { reminder in
                                reminderRow(reminder)
                            }
                            Text("Only reminders due today are shown.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Reminders Debug")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadReminders()
                refreshLinkedReminderIDs()
            }
        }
    }
    
    // MARK: - Row view
    
    @ViewBuilder
    private func reminderRow(_ reminder: EKReminder) -> some View {
        // Clean, non-empty title
        let rawTitle = reminder.title ?? ""
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Untitled" : trimmed
        
        let listName = reminder.calendar?.title
        let isLinked = linkedReminderIDs.contains(reminder.calendarItemIdentifier)
        
        Button {
            link(reminder)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                    
                    if let listName {
                        Text(listName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                if isLinked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "link")
                        .foregroundStyle(.tint)
                }
            }
        }
    }
    
    // MARK: - Load reminders
    
    private func loadReminders() {
        isLoading = true
        errorMessage = nil
        
        ReminderService.shared.fetchTodayReminders(includeCompleted: true) { fetched in
            DispatchQueue.main.async {
                self.reminders = fetched
                self.isLoading = false
                
                // Keep selected list valid
                if !listNames.contains(selectedListName) {
                    selectedListName = allListsOption
                }
                
                print("✅ ReminderListView: loaded \(fetched.count) reminders for today.")
            }
        }
    }
    
    // MARK: - Linked IDs helpers
    
    private func refreshLinkedReminderIDs() {
        let request: NSFetchRequest<HabitReminderLink> = HabitReminderLink.fetchRequest()
        request.predicate = NSPredicate(format: "habit == %@", habit)
        
        do {
            let links = try viewContext.fetch(request)
            linkedReminderIDs = Set(links.compactMap { $0.reminderIdentifier })
            print("✅ ReminderListView: loaded \(linkedReminderIDs.count) linked reminder IDs")
        } catch {
            print("⚠️ ReminderListView: failed to fetch links: \(error)")
        }
    }
    
    // MARK: - Link logic
    
    // MARK: - Link logic
    
    private func link(_ reminder: EKReminder) {
        let identifier = reminder.calendarItemIdentifier
        
        // 🚫 Option A: prevent double-linking this reminder to the same habit
        if linkedReminderIDs.contains(identifier) {
            print("ℹ️ ReminderListView: reminder \(identifier) is already linked to habit '\(habit.name ?? "Habit")'. Skipping.")
            return
        }
        
        // Normalize title to a non-optional, non-empty String
        let rawTitle: String = reminder.title ?? ""
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Untitled" : trimmed
        
        HabitSeeder.upsertLink(
            habit: habit,
            in: viewContext,
            forReminderIdentifier: identifier,
            reminderTitle: title
        )
        
        // Refresh the in-memory set so the UI checkmark updates immediately
        refreshLinkedReminderIDs()
    }
    
}
