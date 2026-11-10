import SwiftUI
import CoreData
import EventKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \Habit.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var habitResults: FetchedResults<Habit>
    
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
        case upgrade
        case settings
        case reminders(Habit)
        case editName(Habit)

        var id: String {
            switch self {
            case .addHabit:
                return "addHabit"
            case .upgrade:
                return "upgrade"
            case .settings:
                return "settings"
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
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()

                        Text("HabitSquares")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .allowsTightening(true)
                            .frame(width: 104, height: 104)
                            .background(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 7)

                        Spacer()
                    }
                    .padding(.top, 4)

                    Group {
                        if habitResults.isEmpty {
                            emptyStateView
                        } else {
                            habitsGridView
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                addHabitButton
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

                case .upgrade:
                    ProUpgradeView(reason: .habitLimit)
                        .environmentObject(purchaseManager)

                case .settings:
                    HabitSquaresSettingsView()
                        .environmentObject(purchaseManager)

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
                        activeSheet = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Text("No habits yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Create yfour first habit square.\nLink Apple Reminders during setup, then watch your daily progress fill in.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 150)
    }

    private var habitsGridView: some View {
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

    private var addHabitButton: some View {
        Button {
            if purchaseManager.canCreateHabit(currentCount: habitResults.count) {
                activeSheet = .addHabit
            } else {
                activeSheet = .upgrade
            }
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
