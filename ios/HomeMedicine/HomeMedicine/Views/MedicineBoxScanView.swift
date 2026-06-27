import SwiftUI
import UIKit

struct MedicineBoxScanView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var quotaStore: UsageQuotaStore

    var onComplete: (MedicineRecognitionResult?, [UIImage?]) -> Void

    private let stepKeys = MedicineBoxFace.stepKeys

    @State private var capturedImages: [UIImage?] = Array(repeating: nil, count: 6)
    @State private var currentStep = 0
    @State private var showCamera = false
    @State private var isRecognizing = false
    @State private var errorMessage: String?
    @State private var paywallTrigger: PaywallTrigger?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        stepProgressPills
                        capturePreviewCard
                        photoOverviewSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                bottomActionBar
            }
            .background(AppTheme.background)
            .navigationTitle(L10n.t("scan.title", locale: localizationManager.locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("action.cancel", locale: localizationManager.locale)) { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(
                    stepTitle: L10n.t(stepKeys[currentStep], locale: localizationManager.locale),
                    stepHint: L10n.t("scan.step_hint", locale: localizationManager.locale),
                    stepIndex: currentStep + 1,
                    totalSteps: stepKeys.count
                ) { image in
                    if let image {
                        capturedImages[currentStep] = image
                        if currentStep < stepKeys.count - 1 {
                            currentStep += 1
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .alert(
                L10n.t("scan.error_title", locale: localizationManager.locale),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(L10n.t("scan.save_photos_only", locale: localizationManager.locale)) {
                    savePhotosOnly()
                }
                Button(L10n.t("action.ok", locale: localizationManager.locale), role: .cancel) {}
            } message: {
                Text(
                    (errorMessage ?? "")
                        + "\n\n"
                        + L10n.t("scan.save_photos_hint", locale: localizationManager.locale)
                )
            }
            .sheet(item: $paywallTrigger) { trigger in
                PaywallView(trigger: trigger)
            }
            .overlay {
                if isRecognizing {
                    recognizingOverlay
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(20)
        .preferredColorScheme(.light)
    }

    private var stepProgressPills: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L10n.t("scan.progress", locale: localizationManager.locale, current: currentStep + 1, total: stepKeys.count))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text("\(filledCount)/\(stepKeys.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.primaryLight)
                    .clipShape(Capsule())
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<stepKeys.count, id: \.self) { index in
                        stepPill(at: index)
                    }
                }
                .padding(.horizontal, 2)
            }

            ProgressView(value: Double(filledCount), total: Double(stepKeys.count))
                .tint(AppTheme.primary)
        }
        .padding(16)
        .cardStyle()
    }

    private func stepPill(at index: Int) -> some View {
        let isCurrent = index == currentStep
        let isFilled = capturedImages[index] != nil

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                currentStep = index
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isFilled ? AppTheme.primary : (isCurrent ? AppTheme.primary.opacity(0.15) : AppTheme.searchBackground))
                        .frame(width: 22, height: 22)
                    if isFilled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isCurrent ? AppTheme.primary : AppTheme.textMuted)
                    }
                }
                Text(L10n.t(stepKeys[index], locale: localizationManager.locale))
                    .font(.caption.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? AppTheme.primary : AppTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isCurrent ? AppTheme.primaryLight : AppTheme.cardBackground)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isCurrent ? AppTheme.primary.opacity(0.35) : AppTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var capturePreviewCard: some View {
        Button {
            showCamera = true
        } label: {
            ZStack {
                if let image = capturedImages[currentStep] {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AppTheme.primaryLight, AppTheme.cardBackground],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 220)
                        .overlay {
                            VStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(AppTheme.primary.opacity(0.12))
                                        .frame(width: 72, height: 72)
                                    Image(systemName: "camera.viewfinder")
                                        .font(.system(size: 32, weight: .medium))
                                        .foregroundStyle(AppTheme.primary)
                                        .symbolRenderingMode(.hierarchical)
                                }
                                Text(L10n.t(stepKeys[currentStep], locale: localizationManager.locale))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                Text(L10n.t("scan.step_hint", locale: localizationManager.locale))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                        }
                }

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        capturedImages[currentStep] == nil
                            ? AppTheme.primary.opacity(0.25)
                            : Color.clear,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .frame(height: 220)

                VStack {
                    HStack {
                        Text(L10n.t(stepKeys[currentStep], locale: localizationManager.locale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.45))
                            .clipShape(Capsule())
                        Spacer()
                        if capturedImages[currentStep] != nil {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.black.opacity(0.45))
                                .clipShape(Circle())
                        }
                    }
                    .padding(12)
                    Spacer()
                }
                .frame(height: 220)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: AppTheme.primary.opacity(0.12), radius: 12, y: 6)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var photoOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("section.box_photos", locale: localizationManager.locale))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(0..<stepKeys.count, id: \.self) { index in
                    photoCell(at: index)
                }
            }
        }
    }

    private func photoCell(at index: Int) -> some View {
        Button {
            currentStep = index
            showCamera = true
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(index == currentStep ? AppTheme.primaryLight : AppTheme.searchBackground)
                        .frame(height: 80)
                    if let image = capturedImages[index] {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, AppTheme.primary)
                                    .padding(4)
                            }
                    } else {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                            .foregroundStyle(index == currentStep ? AppTheme.primary : AppTheme.textMuted)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(index == currentStep ? AppTheme.primary.opacity(0.4) : Color.clear, lineWidth: 2)
                )
                Text(L10n.t(stepKeys[index], locale: localizationManager.locale))
                    .font(.caption2)
                    .foregroundStyle(index == currentStep ? AppTheme.primary : AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            Button {
                showCamera = true
            } label: {
                Label(L10n.t("scan.take_photo", locale: localizationManager.locale), systemImage: "camera.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.minTouchTarget)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryDark],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: AppTheme.primary.opacity(0.28), radius: 8, y: 4)
            }
            .buttonStyle(PressableButtonStyle())

            Button(action: recognize) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text(L10n.t("scan.recognize", locale: localizationManager.locale))
                }
                .font(.headline)
                .foregroundStyle(canRecognize ? AppTheme.primary : AppTheme.textMuted)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.minTouchTarget)
                .background(canRecognize ? AppTheme.primaryLight : AppTheme.searchBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(canRecognize ? AppTheme.primary.opacity(0.25) : AppTheme.border, lineWidth: 1)
                )
            }
            .disabled(!canRecognize || isRecognizing)
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(
            AppTheme.cardBackground
                .shadow(color: .black.opacity(0.06), radius: 8, y: -2)
        )
    }

    private var recognizingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(AppTheme.primaryLight)
                        .frame(width: 64, height: 64)
                    ProgressView()
                        .tint(AppTheme.primary)
                        .scaleEffect(1.3)
                }
                Text(L10n.t("scan.recognizing", locale: localizationManager.locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
        }
    }

    private var filledCount: Int {
        capturedImages.compactMap { $0 }.count
    }

    private var canRecognize: Bool {
        filledCount >= 1
    }

    private func savePhotosOnly() {
        errorMessage = nil
        onComplete(nil, capturedImages)
        dismiss()
    }

    private func recognize() {
        let images = capturedImages.compactMap { $0 }
        guard !images.isEmpty else { return }

        guard quotaStore.canUseAIScan(tier: subscriptionManager.tier) else {
            paywallTrigger = .aiScanLimit
            return
        }

        isRecognizing = true
        Task {
            do {
                let result = try await BailianVisionService.recognizeMedicine(from: images)
                guard quotaStore.consumeAIScan(tier: subscriptionManager.tier) else {
                    await MainActor.run {
                        isRecognizing = false
                        paywallTrigger = .aiScanLimit
                    }
                    return
                }
                await MainActor.run {
                    isRecognizing = false
                    onComplete(result, capturedImages)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isRecognizing = false
                    if let visionError = error as? BailianVisionError {
                        errorMessage = visionError.localizedMessage(locale: localizationManager.locale)
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
}
