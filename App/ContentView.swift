import SwiftUI
import CoreData
import EventKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Habit.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var habitResults: FetchedResults<Habit>
    
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @State private var showingHowItWorks = false

    @State private var path = NavigationPath()
    @State private var activeSheet: ActiveSheet?
    @State private var habitPendingDelete: Habit?

    @AppStorage("lastHistoryBackfillDay")
    private var lastHistoryBackfillDay: Double = 0

    private var habitsByNewest: [Habit] {
        habitResults.sorted { lhs, rhs in
            (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
    }

    private enum ActiveSheet: Identifiable {
        case addHabit
        case reminders(Habit)
        case editName(Habit)

        var id: String {
            switch self {
            case .addHabit:
                return "addHabit"
            case .reminders(let habit):
                return "reminders-\(habit.objectID.uriRepresentation().absoluteString)"
            case .editName(let habit):
                return "editName-\(habit.objectID.uriRepresentation().absoluteString)"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()

                        Text("habitSquares")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .frame(width: 92, height: 92)
                            .background(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 26, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)

                        Spacer()
                    }
                    .padding(.top, 4)

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
                            GeometryReader { geo in
                                let horizontalPadding: CGFloat = 16
                                let spacing: CGFloat = 12
                                let availableWidth = geo.size.width - (horizontalPadding * 2) - spacing
                                let cardWidth = floor(availableWidth / 2)
                                let compactCards = cardWidth < 185

                                ScrollView {
                                    LazyVGrid(
                                        columns: [
                                            GridItem(.fixed(cardWidth), spacing: spacing),
                                            GridItem(.fixed(cardWidth), spacing: spacing)
                                        ],
                                        spacing: spacing
                                    ) {
                                        ForEach(habitsByNewest, id: \.objectID) { habit in
                                            Button {
                                                path.append(habit.objectID)
                                            } label: {
                                                HabitHeatmapView(
                                                    habit: habit,
                                                    compactLayout: compactCards
                                                )
                                                .frame(width: cardWidth, alignment: .topLeading)
                                            }
                                            .buttonStyle(HabitCardButtonStyle())
                                            .contentShape(Rectangle())
                                            .contextMenu {
                                                Button {
                                                    activeSheet = .editName(habit)
                                                } label: {
                                                    Label("Edit Habit", systemImage: "pencil")
                                                }

                                                Button(role: .destructive) {
                                                    habitPendingDelete = habit
                                                } label: {
                                                    Label("Delete Habit", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                    .padding(.horizontal, horizontalPadding)
                                    .padding(.bottom, 100)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

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
            .navigationDestination(for: NSManagedObjectID.self) { objectID in
                if let habit = viewContext.object(with: objectID) as? Habit {
                    HabitDetailView(habit: habit)
                } else {
                    Text("Habit not found")
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addHabit:
                    AddHabitView()
                        .environment(\.managedObjectContext, viewContext)

                case .reminders(let habit):
                    ReminderListView(habit: habit)
                        .environment(\.managedObjectContext, viewContext)

                case .editName(let habit):
                    EditHabitSheet(habit: habit)
                        .environment(\.managedObjectContext, viewContext)
                }
            }
            .onAppear {
                logCoreDataHabits("onAppear")
                syncTodayAndHistoryIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    WidgetRefresh.push(viewContext)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                syncTodayOnly()
            }
            .confirmDelete(
                item: $habitPendingDelete,
                title: "Delete habit?",
                message: "This will remove the habit and its linked data from HabitSquares.",
                confirmTitle: "Delete Habit"
            ) { habit in
                deleteHabit(habit)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingHowItWorks = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("How HabitSquares works")
                }
            }
            Button("Show Onboarding Again") {
                hasSeenOnboarding = false
            }
            .sheet(isPresented: $showingHowItWorks) {
                HowItWorksView()
            }        }
    }

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

    private func syncTodayOnly() {
        HabitCompletionEngine.syncTodayFromReminders(in: viewContext)
    }

    private func syncTodayAndHistoryIfNeeded(force: Bool = false) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date()).timeIntervalSince1970
        let last = cal.startOfDay(
            for: Date(timeIntervalSince1970: lastHistoryBackfillDay)
        ).timeIntervalSince1970

        let needsBackfill = force || (last == 0) || (last != today)

        if needsBackfill {
            lastHistoryBackfillDay = today
            HabitCompletionEngine.syncLast365DaysFromReminders(in: viewContext)
        }

        syncTodayOnly()
    }

    private func deleteHabit(_ habit: Habit) {
        viewContext.delete(habit)
        do {
            try viewContext.save()
        } catch {
            print("❌ Failed to delete habit: \(error)")
        }
    }

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
