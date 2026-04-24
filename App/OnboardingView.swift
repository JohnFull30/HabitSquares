//
//  OnboardingView.swift
//  Habit Tracker
//
//  Created by John Fuller on 4/24/26.
//


import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0

    private let pages = OnboardingPage.pages

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Button("Skip") {
                    hasSeenOnboarding = true
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal)
                .padding(.top, 12)
            }

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingCardView(page: page)
                        .tag(index)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            VStack(spacing: 12) {
                Button {
                    if currentPage < pages.count - 1 {
                        currentPage += 1
                    } else {
                        hasSeenOnboarding = true
                    }
                } label: {
                    Text(currentPage == pages.count - 1 ? "Start Tracking" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)

                if currentPage > 0 {
                    Button("Back") {
                        currentPage -= 1
                    }
                    .font(.subheadline.weight(.medium))
                } else {
                    Color.clear
                        .frame(height: 20)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }
}

private struct OnboardingCardView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.thinMaterial)
                    .frame(width: 150, height: 150)

                Image(systemName: page.systemImage)
                    .font(.system(size: 54, weight: .semibold))
            }

            VStack(spacing: 12) {
                Text(page.title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Spacer()
        }
    }
}