import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var quotaStore: UsageQuotaStore
    @EnvironmentObject private var localizationManager: LocalizationManager

    let trigger: PaywallTrigger

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    benefits
                    subscriptionSection
                    creditsSection
                    legalFooter
                }
                .padding(20)
            }
            .background(AppTheme.background)
            .navigationTitle(L10n.t("paywall.title", locale: localizationManager.locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("action.close", locale: localizationManager.locale)) { dismiss() }
                }
            }
            .overlay {
                if subscriptionManager.isPurchasing {
                    ProgressView()
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert(
                L10n.t("paywall.error_title", locale: localizationManager.locale),
                isPresented: Binding(
                    get: { subscriptionManager.purchaseErrorMessage != nil },
                    set: { if !$0 { subscriptionManager.purchaseErrorMessage = nil } }
                )
            ) {
                Button(L10n.t("action.ok", locale: localizationManager.locale), role: .cancel) {}
            } message: {
                Text(subscriptionManager.purchaseErrorMessage ?? "")
            }
            .onChange(of: subscriptionManager.tier) { _, tier in
                if trigger == .familySharing, EntitlementChecker.canUseFamilySharing(tier: tier) {
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.primary)
            Text(triggerTitle)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text(L10n.t("paywall.subtitle", locale: localizationManager.locale))
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            if subscriptionManager.tier != .free {
                Text(L10n.t("paywall.current_plan.\(subscriptionManager.tier.rawValue)", locale: localizationManager.locale))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppTheme.primaryLight)
                    .clipShape(Capsule())
            }
            Text(L10n.t("paywall.ai_remaining", locale: localizationManager.locale, count: quotaStore.remainingAIScans(tier: subscriptionManager.tier)))
                .font(.caption)
                .foregroundStyle(AppTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardStyle(borderColor: AppTheme.primary.opacity(0.25))
    }

    private var triggerTitle: String {
        L10n.t("paywall.trigger.\(trigger.rawValue)", locale: localizationManager.locale)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 10) {
            benefitRow("infinity", L10n.t("paywall.benefit.medicines", locale: localizationManager.locale))
            benefitRow("camera.viewfinder", L10n.t("paywall.benefit.ai_scans", locale: localizationManager.locale))
            benefitRow("bell.badge", L10n.t("paywall.benefit.reminders", locale: localizationManager.locale))
            benefitRow("person.3", L10n.t("paywall.benefit.members", locale: localizationManager.locale))
            benefitRow("square.and.arrow.up", L10n.t("paywall.benefit.export", locale: localizationManager.locale))
        }
        .padding(16)
        .cardStyle()
    }

    private func benefitRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("paywall.section.subscription", locale: localizationManager.locale))
                .font(.headline)

            if let yearly = subscriptionManager.product(for: SubscriptionProductID.proYearly) {
                subscriptionButton(
                    product: yearly,
                    title: L10n.t("paywall.plan.pro_yearly", locale: localizationManager.locale),
                    badge: L10n.t("paywall.best_value", locale: localizationManager.locale),
                    highlighted: true
                )
            }

            if let monthly = subscriptionManager.product(for: SubscriptionProductID.proMonthly) {
                subscriptionButton(
                    product: monthly,
                    title: L10n.t("paywall.plan.pro_monthly", locale: localizationManager.locale),
                    badge: nil,
                    highlighted: false
                )
            }

            if let family = subscriptionManager.product(for: SubscriptionProductID.familyYearly) {
                subscriptionButton(
                    product: family,
                    title: L10n.t("paywall.plan.family_yearly", locale: localizationManager.locale),
                    badge: L10n.t("paywall.family_badge", locale: localizationManager.locale),
                    highlighted: false
                )
            }

            if subscriptionManager.products.isEmpty && !subscriptionManager.isLoadingProducts {
                Text(L10n.t("paywall.products_unavailable", locale: localizationManager.locale))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textMuted)
            }

            Button(L10n.t("paywall.restore", locale: localizationManager.locale)) {
                Task { await subscriptionManager.restorePurchases() }
            }
            .font(.caption)
            .foregroundStyle(AppTheme.primary)
            .frame(maxWidth: .infinity)
        }
    }

    private func subscriptionButton(product: Product, title: String, badge: String?, highlighted: Bool) -> some View {
        Button {
            Task { await subscriptionManager.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.amber)
                                .clipShape(Capsule())
                        }
                    }
                    Text(product.displayPrice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(highlighted ? .white : AppTheme.textPrimary)
            .padding(16)
            .background(highlighted ? AppTheme.primary : AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                if !highlighted {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(AppTheme.border, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing)
    }

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("paywall.section.credits", locale: localizationManager.locale))
                .font(.headline)
            Text(L10n.t("paywall.credits_hint", locale: localizationManager.locale))
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: 10) {
                creditButton(productID: SubscriptionProductID.aiCredits10, count: 10)
                creditButton(productID: SubscriptionProductID.aiCredits30, count: 30)
                creditButton(productID: SubscriptionProductID.aiCredits100, count: 100)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func creditButton(productID: String, count: Int) -> some View {
        Button {
            guard let product = subscriptionManager.product(for: productID) else { return }
            Task { await subscriptionManager.purchase(product) }
        } label: {
            VStack(spacing: 6) {
                Text(L10n.t("paywall.credits_count", locale: localizationManager.locale, count: count))
                    .font(.caption.weight(.semibold))
                if let product = subscriptionManager.product(for: productID) {
                    Text(product.displayPrice)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(AppTheme.textMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(AppTheme.primaryLight)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(subscriptionManager.isPurchasing || subscriptionManager.product(for: productID) == nil)
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                Link(L10n.t("paywall.privacy_policy", locale: localizationManager.locale), destination: Self.privacyPolicyURL)
                Text("·")
                    .foregroundStyle(AppTheme.textMuted)
                Link(L10n.t("paywall.terms_of_use", locale: localizationManager.locale), destination: Self.termsOfUseURL)
            }
            .font(.caption)
            .foregroundStyle(AppTheme.primary)

            Text(L10n.t("paywall.legal", locale: localizationManager.locale))
                .font(.caption2)
                .foregroundStyle(AppTheme.textMuted)
                .multilineTextAlignment(.center)
            Text(L10n.t("paywall.disclaimer", locale: localizationManager.locale))
                .font(.caption2)
                .foregroundStyle(AppTheme.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private static let privacyPolicyURL = URL(string: "http://app.gptdevelop.cn/privacy.html")!
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
