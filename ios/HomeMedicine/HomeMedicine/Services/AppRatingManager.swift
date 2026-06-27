import Foundation
import StoreKit
import UIKit

@MainActor
final class AppRatingManager {
    static let shared = AppRatingManager()

    private init() {}

    func recordLaunchIfNeeded(settings: SettingsStore) {
        if settings.firstLaunchDate == nil {
            settings.firstLaunchDate = Date()
        }
    }

    func requestReviewIfEligible(settings: SettingsStore) {
        guard let firstLaunch = settings.firstLaunchDate else { return }
        let daysUsed = Calendar.current.dateComponents([.day], from: firstLaunch, to: Date()).day ?? 0
        guard daysUsed >= 1 else { return }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        if settings.lastReviewPromptVersion == currentVersion { return }

        if let lastPrompt = settings.lastReviewPromptDate,
           Calendar.current.dateComponents([.day], from: lastPrompt, to: Date()).day ?? 0 < 30 {
            return
        }

        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
            settings.lastReviewPromptVersion = currentVersion
            settings.lastReviewPromptDate = Date()
        }
    }
}
