//
//  HabitSquaresSettingsView.swift
//  Habit Tracker
//
//  Created by John Fuller on 5/2/26.
//


import SwiftUI

struct HabitSquaresSettingsView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @State private var activeSheet: SettingsSheet?

    private enum SettingsSheet: Identifiable {
        case upgrade
        case customTip

        var id: String {
            switch self {
            case .upgrade:
                return "upgrade"
            case .customTip:
                return "customTip"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HabitSquares")
                            .font(.title2.weight(.bold))

                        Text("Track habits with a GitHub-style heatmap powered by your linked Apple Reminders.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Founder Lifetime Pro") {
                    if purchaseManager.isPro {
                        Label("Unlimited habits unlocked", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            activeSheet = .upgrade
                        } label: {
                            Label("Unlock Unlimited Habits", systemImage: "infinity")
                        }

                        Text("Free users can create up to \(PurchaseManager.freeHabitLimit) habits.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Restore Purchases") {
                        Task {
                            await purchaseManager.restorePurchases()
                        }
                    }

                    if let errorMessage = purchaseManager.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                TipDeveloperView {
                    activeSheet = .customTip
                }

                Section("How it works") {
                    Label("Create habits owned by HabitSquares", systemImage: "square.grid.3x3")
                    Label("Link one or more Apple Reminders", systemImage: "checklist")
                    Label("Required reminders decide completion", systemImage: "checkmark.seal")
                    Label("Green means all required reminders were completed that day", systemImage: "calendar.badge.checkmark")
                }

                Section("Reminders") {
                    Text("When a reminder is linked to a habit, HabitSquares checks whether the required reminders were completed for that day. For recurring reminders, completion is based on the reminder completion date, not just the current due date.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Section("Widgets") {
                    Text("Widgets show a quick snapshot of today’s habit progress. If a widget looks slightly behind, opening HabitSquares refreshes the latest reminder and habit status.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                if AppFlags.showDevTools {
                    Section("Developer") {
                        Button {
                            hasSeenOnboarding = false
                        } label: {
                            Label("Show Onboarding Again", systemImage: "arrow.counterclockwise")
                        }
                    }
                }
                #endif

                Section("Privacy") {
                    Text("HabitSquares uses Apple Reminders permission only so you can link reminders to habits and calculate daily completion. Your habit data stays in your app data unless you later enable iCloud syncing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .upgrade:
                    ProUpgradeView(reason: .settings)
                        .environmentObject(purchaseManager)
                case .customTip:
                    CustomTipView()
                        .environmentObject(purchaseManager)
                }
            }
            .task {
                if purchaseManager.products.isEmpty {
                    await purchaseManager.loadProducts()
                }
            }
        }
    }
}
