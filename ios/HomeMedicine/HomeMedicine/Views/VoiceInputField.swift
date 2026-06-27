import SwiftUI

struct VoiceInputSheet: View {
    let fieldTitle: String
    let locale: Locale
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechRecognizer: SpeechRecognizer
    @State private var transcript = ""
    @State private var showError = false

    init(fieldTitle: String, locale: Locale, onConfirm: @escaping (String) -> Void) {
        self.fieldTitle = fieldTitle
        self.locale = locale
        self.onConfirm = onConfirm
        _speechRecognizer = StateObject(wrappedValue: SpeechRecognizer(locale: locale))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                recordingIndicator

                ScrollView {
                    Text(displayText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.body)
                        .foregroundStyle(transcript.isEmpty ? AppTheme.textMuted : AppTheme.textPrimary)
                        .padding(16)
                }
                .frame(maxHeight: .infinity)
                .background(AppTheme.searchBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 12) {
                    Button(L10n.t("action.cancel", locale: locale)) {
                        cancel()
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                    Button(L10n.t("action.confirm", locale: locale)) {
                        confirm()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                    .frame(maxWidth: .infinity)
                    .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .navigationTitle(fieldTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(300), .medium])
        .presentationDragIndicator(.visible)
        .onAppear(perform: startRecording)
        .onDisappear {
            speechRecognizer.stopRecording()
        }
        .alert(
            L10n.t("voice.error_title", locale: locale),
            isPresented: $showError
        ) {
            Button(L10n.t("action.ok", locale: locale), role: .cancel) {}
        } message: {
            Text(speechRecognizer.errorMessage ?? "")
        }
        .onChange(of: speechRecognizer.errorMessage) { _, message in
            showError = message != nil
        }
    }

    private var displayText: String {
        transcript.isEmpty ? L10n.t("voice.prompt", locale: locale) : transcript
    }

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: speechRecognizer.isRecording ? "mic.fill" : "mic.slash")
                .foregroundStyle(speechRecognizer.isRecording ? AppTheme.expired : AppTheme.textMuted)
            Text(
                speechRecognizer.isRecording
                    ? L10n.t("voice.listening", locale: locale)
                    : L10n.t("voice.stopped", locale: locale)
            )
            .font(.caption)
            .foregroundStyle(AppTheme.textSecondary)
            if speechRecognizer.isRecording {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startRecording() {
        transcript = ""
        Task {
            await speechRecognizer.startRecording { partial in
                transcript = partial
            }
        }
    }

    private func confirm() {
        speechRecognizer.stopRecording()
        onConfirm(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }

    private func cancel() {
        speechRecognizer.stopRecording()
        dismiss()
    }
}

struct VoiceInputField: View {
    let title: String
    @Binding var text: String
    let locale: Locale
    var axis: Axis = .horizontal

    @State private var showVoiceSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
                Button { showVoiceSheet = true } label: {
                    Image(systemName: "mic")
                        .font(.body)
                        .foregroundStyle(AppTheme.primary)
                        .frame(width: AppTheme.minTouchTarget, height: 32)
                }
                .accessibilityLabel(L10n.t("voice.start", locale: locale))
            }

            if axis == .vertical {
                TextField(title, text: $text, axis: .vertical)
                    .lineLimit(3...6)
            } else {
                TextField(title, text: $text)
            }
        }
        .sheet(isPresented: $showVoiceSheet) {
            VoiceInputSheet(fieldTitle: title, locale: locale) { transcript in
                text = transcript
            }
        }
    }
}
