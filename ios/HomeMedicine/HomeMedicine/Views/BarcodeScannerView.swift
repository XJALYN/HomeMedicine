import SwiftUI
import AVFoundation
import Vision

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onScan = { code in
            onScan(code)
            dismiss()
        }
        controller.onCancel = { dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private let session = AVCaptureSession()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
        setupOverlay()
    }

    private func setupCamera() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        session.startRunning()
    }

    private func setupOverlay() {
        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.tintColor = .white
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
        ])
    }

    @objc private func cancelTapped() { onCancel?() }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        session.stopRunning()
        onScan?(value)
    }
}

struct ExpiryOCRView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var recognizedText = ""
    @State private var suggestedDate: Date?
    var onConfirm: (Date) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(L10n.t("ocr.hint", locale: localizationManager.locale))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding()

                TextField(L10n.t("ocr.manual_input", locale: localizationManager.locale), text: $recognizedText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Button(L10n.t("ocr.recognize", locale: localizationManager.locale)) {
                    suggestedDate = ExpiryOCRService.suggestDate(from: recognizedText)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)

                if let suggestedDate {
                    DatePicker(
                        L10n.t("field.expiry_date", locale: localizationManager.locale),
                        selection: Binding(get: { suggestedDate }, set: { self.suggestedDate = $0 }),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding()

                    Button(L10n.t("action.confirm", locale: localizationManager.locale)) {
                        onConfirm(suggestedDate)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primary)
                }

                Spacer()
            }
            .navigationTitle(L10n.t("ocr.title", locale: localizationManager.locale))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("action.cancel", locale: localizationManager.locale)) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }
}
