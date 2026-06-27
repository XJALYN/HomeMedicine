import CloudKit
import SwiftUI
import UIKit

struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onComplete: () -> Void
    var onError: ((String) -> Void)?

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete, onError: onError)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let onComplete: () -> Void
        private let onError: ((String) -> Void)?

        init(onComplete: @escaping () -> Void, onError: ((String) -> Void)?) {
            self.onComplete = onComplete
            self.onError = onError
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onError?(error.localizedDescription)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            csc.share?[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onComplete()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onComplete()
        }
    }
}
