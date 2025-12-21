import SwiftUI
import CoreData
import EventKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase

    // Core Data fetch for all habits (newest first)
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Habit.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var habitResults: FetchedResults<Habit>

    // Programmatic navigation (keeps LazyVGrid spacing stable)
    @State private var path = NavigationPath()

    // Which sheet is currently active
    @State private var activeSheet: ActiveSheet?

    // Newest-first array for grid rendering
    private var habitsByNewest: [Habit] {
        habitResults.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
    }

    // MARK: - Sheet routing

    private enum ActiveSheet: Identifiable {
        case addHabit
        case reminders(Habit)

        // Unique ID so SwiftUI can distinguish sheets
        var id: String {
            switch self {
            case .addHabit:
                return "addHabit"
            case .reminders(let habit):
                // Use the Core Data objectID URI for uniqueness
                return "reminders-\(habit.objectID.uriRepresentation().absoluteString)"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                // MAIN LAYOUT: header + content
                VStack(alignment: .leading, spacing: 16) {

                    // HEADER – as high as possible
                    HStack(alignment: .center) {
                        Text("habitSquares")
                            .font(.largeTitle.weight(.bold))

                        Spacer()
                        // (No + button up here anymore)
                    }
                    .hsCard()
                    .padding(.horizontal)
                    .padding(.top, 4)

                    // CONTENT
                    Group {
                        if habitResults.isEmpty {
                            VStack(spacing: 12) {
                                Text("No habits yet.")
                                    .font(.headline)
                                Text("Tap the button below to add your first habit.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 16),
                                        GridItem(.flexible(), spacing: 16)
                                    ],
                                    spacing: 16
                                ) {
                                    ForEach(habitsByNewest, id: \.objectID) { habit in
                                        Button {
                                            // Tap card → navigate to details (no NavigationLink layout side-effects)
                                            path.append(habit.objectID)
                                        } label: {
                                            habitCardStyle {
                                                HabitHeatmapView(habit: habit)
                                            }
                                        }
                                        .buttonStyle(HabitCardButtonStyle())
                                        .contentShape(Rectangle())
                                        .contextMenu {
                                            Button {
                                                activeSheet = .reminders(habit)
                                            } label: {
                                                Label("Link Reminders", systemImage: "link")
                                            }

                                            Button(role: .destructive) {
                                                deleteHabit(habit)
                                            } label: {
                                                Label("Delete Habit", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 100) // space so grid doesn't sit under the bottom button
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // FLOATING BOTTOM "ADD HABIT" BUTTON
                Button {
                    activeSheet = .addHabit
                } label: {
                    Label("Add Habit", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                        )
                        .foregroundColor(.white)
                        .shadow(
                            color: .black.opacity(0.15),
                            radius: 10,
                            x: 0,
                            y: 4
                        )
                }
                .padding(.bottom, 32)
            }

            // Navigate to HabitDetailView using Core Data objectID
            .navigationDestination(for: NSManagedObjectID.self) { objectID in
                if let habit = viewContext.object(with: objectID) as? Habit {
                    HabitDetailView(habit: habit)
                } else {
                    Text("Habit not found")
                }
            }

            // SHEETS
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addHabit:
                    AddHabitView()
                        .environment(\.managedObjectContext, viewContext)

                case .reminders(let habit):
                    ReminderListView(habit: habit)
                        .environment(\.managedObjectContext, viewContext)
                }
            }

            // SYNC + LOGGING
            .onAppear {
                logCoreDataHabits("onAppear")
                syncTodayFromReminders()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    syncTodayFromReminders()
                }
            }
            // ✅ NEW: Re-sync when EventKit says Reminders changed
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                syncTodayFromReminders()
            }
        }
        // Hide default nav bar so our custom header can sit as high as possible
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Card styling helper

    private func habitCardStyle<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.thinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .padding(.vertical, 4)
    }

    // MARK: - Habit card button style (press feedback)

    struct HabitCardButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .shadow(
                    color: .black.opacity(configuration.isPressed ? 0.02 : 0.06),
                    radius: configuration.isPressed ? 2 : 6,
                    x: 0,
                    y: configuration.isPressed ? 1 : 4
                )
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }

    // MARK: - Sync Reminders → HabitCompletion

    private func syncTodayFromReminders() {
        ReminderService.shared.fetchTodayReminders(includeCompleted: true) { fetched in
            Task { @MainActor in
                print("✅ syncTodayFromReminders: fetched \(fetched.count) reminders for today.")

                HabitCompletionEngine.upsertCompletionsForToday(
                    in: viewContext,
                    reminders: fetched
                )
            }
        }
    }

    // MARK: - Delete habits from List (kept for future use)

    private func deleteHabits(at offsets: IndexSet) {
        for index in offsets {
            let habit = habitResults[index]
            viewContext.delete(habit)
        }

        do {
            try viewContext.save()
            print("✅ Deleted \(offsets.count) habit(s).")
        } catch {
            print("❌ Failed to delete habit(s): \(error)")
        }
    }

    // MARK: - Delete a single habit from grid

    private func deleteHabit(_ habit: Habit) {
        viewContext.delete(habit)
        do {
            try viewContext.save()
            print("🗑 Deleted habit '\(habit.name ?? "<unnamed>")'")
        } catch {
            print("❌ Failed to delete habit: \(error)")
        }
    }

    // MARK: - Debug helpers

    private func logCoreDataHabits(_ label: String) {
        print("===== Core Data habits (\(label)) =====")
        for habit in habitResults {
            let id = habit.id?.uuidString ?? "nil"
            let name = habit.name ?? "<unnamed>"
            print(" - id: \(id), name: \(name)")
        }
        print("===== end =====")
    }
}
