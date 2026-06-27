import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    var stepTitle: String?
    var stepHint: String?
    var stepIndex: Int?
    var totalSteps: Int?
    var onCapture: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.modalPresentationStyle = .fullScreen

        if picker.sourceType == .camera, let stepTitle {
            let overlay = CameraGuideOverlayView(
                stepTitle: stepTitle,
                stepHint: stepHint ?? "",
                stepIndex: stepIndex,
                totalSteps: totalSteps
            )
            overlay.frame = UIScreen.main.bounds
            overlay.isUserInteractionEnabled = false
            picker.cameraOverlayView = overlay
            picker.cameraViewTransform = .identity
        }

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (UIImage?) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onCapture(info[.originalImage] as? UIImage)
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private final class CameraGuideOverlayView: UIView {
    private let stepTitle: String
    private let stepHint: String
    private let stepIndex: Int?
    private let totalSteps: Int?

    private let guideLayer = CAShapeLayer()
    private let cornerLayer = CAShapeLayer()
    private let titleLabel = UILabel()
    private let badgeLabel = UILabel()
    private let hintLabel = UILabel()
    private let topGradient = CAGradientLayer()
    private let bottomGradient = CAGradientLayer()
    private var guideRect: CGRect = .zero

    /// Space reserved above the home indicator for the system shutter button.
    private static let shutterClearance: CGFloat = 116

    init(stepTitle: String, stepHint: String, stepIndex: Int?, totalSteps: Int?) {
        self.stepTitle = stepTitle
        self.stepHint = stepHint
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        super.init(frame: .zero)
        isOpaque = false
        setupLayers()
        setupLabels()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutGuideFrame()
        layoutGradients()
        layoutLabels()
    }

    private func setupLayers() {
        guideLayer.fillColor = UIColor.clear.cgColor
        guideLayer.strokeColor = UIColor.white.withAlphaComponent(0.92).cgColor
        guideLayer.lineWidth = 2.5
        guideLayer.lineDashPattern = [10, 7]
        layer.addSublayer(guideLayer)

        cornerLayer.fillColor = UIColor.clear.cgColor
        cornerLayer.strokeColor = UIColor(
            red: 0.06, green: 0.73, blue: 0.51, alpha: 1
        ).cgColor
        cornerLayer.lineWidth = 3.5
        cornerLayer.lineCap = .round
        layer.addSublayer(cornerLayer)

        topGradient.colors = [
            UIColor.black.withAlphaComponent(0.55).cgColor,
            UIColor.clear.cgColor
        ]
        bottomGradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.55).cgColor
        ]
        layer.addSublayer(topGradient)
        layer.addSublayer(bottomGradient)
    }

    private func setupLabels() {
        if let stepIndex, let totalSteps {
            badgeLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            badgeLabel.textColor = .white
            badgeLabel.textAlignment = .center
            badgeLabel.text = "\(stepIndex)/\(totalSteps)"
            badgeLabel.backgroundColor = UIColor(red: 0.06, green: 0.73, blue: 0.51, alpha: 1)
            badgeLabel.layer.cornerRadius = 12
            badgeLabel.layer.masksToBounds = true
            addSubview(badgeLabel)
        }

        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.text = stepTitle
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOpacity = 0.35
        titleLabel.layer.shadowRadius = 4
        titleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(titleLabel)

        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.92)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        hintLabel.text = stepHint
        hintLabel.layer.shadowColor = UIColor.black.cgColor
        hintLabel.layer.shadowOpacity = 0.35
        hintLabel.layer.shadowRadius = 4
        hintLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(hintLabel)
    }

    private func layoutGuideFrame() {
        let inset: CGFloat = 28
        let maxWidth = bounds.width - inset * 2
        let maxHeight = bounds.height * 0.46
        var guideWidth = maxWidth
        var guideHeight = guideWidth * 1.25
        if guideHeight > maxHeight {
            guideHeight = maxHeight
            guideWidth = guideHeight / 1.25
        }
        guideRect = CGRect(
            x: (bounds.width - guideWidth) / 2,
            y: (bounds.height - guideHeight) / 2 - 16,
            width: guideWidth,
            height: guideHeight
        )
        let path = UIBezierPath(roundedRect: guideRect, cornerRadius: 18)
        guideLayer.path = path.cgPath
        cornerLayer.path = cornerPath(in: guideRect, length: 22).cgPath
    }

    private func cornerPath(in rect: CGRect, length: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let inset: CGFloat = 1

        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY + inset))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY - inset))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY - length))

        return path
    }

    private func layoutGradients() {
        topGradient.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height * 0.22)
        bottomGradient.frame = CGRect(
            x: 0,
            y: bounds.height * 0.72,
            width: bounds.width,
            height: bounds.height * 0.28
        )
    }

    private func layoutLabels() {
        let safeTop = safeAreaInsets.top + 12
        let badgeSize = CGSize(width: 52, height: 24)
        badgeLabel.frame = CGRect(
            x: (bounds.width - badgeSize.width) / 2,
            y: safeTop,
            width: badgeSize.width,
            height: badgeSize.height
        )

        titleLabel.frame = CGRect(
            x: 24,
            y: badgeLabel.frame.maxY + 10,
            width: bounds.width - 48,
            height: 28
        )

        let hintWidth = bounds.width - 64
        let maxHintBottom = bounds.height - safeAreaInsets.bottom - Self.shutterClearance
        let preferredHintY = guideRect.maxY + 14
        let fittedHeight = hintLabel.sizeThatFits(
            CGSize(width: hintWidth, height: .greatestFiniteMagnitude)
        ).height
        let hintHeight = min(fittedHeight, max(36, maxHintBottom - preferredHintY))
        let hintY = min(preferredHintY, maxHintBottom - hintHeight)

        hintLabel.frame = CGRect(
            x: 32,
            y: hintY,
            width: hintWidth,
            height: hintHeight
        )
    }
}
