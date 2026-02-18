import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

enum DocumentPickerRequest: Equatable {
    case export(url: URL)
    case `import`
}

#if canImport(UIKit)
struct DocumentPickerHost: UIViewControllerRepresentable {
    @Binding var request: DocumentPickerRequest?
    let onExportResult: (Result<URL, Error>) -> Void
    let onImportResult: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let request else { return }
        context.coordinator.enqueue(request: request)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: DocumentPickerHost
        private var activeRequest: DocumentPickerRequest?
        private var isPresenting = false
        private var pendingRequest: DocumentPickerRequest?

        init(parent: DocumentPickerHost) {
            self.parent = parent
        }

        func enqueue(request: DocumentPickerRequest) {
            pendingRequest = request
            DispatchQueue.main.async {
                self.parent.request = nil
                if self.isPresenting { return }
                self.presentIfPossible()
            }
        }

        private func presentIfPossible() {
            guard let request = pendingRequest else {
                isPresenting = false
                return
            }
            isPresenting = true
            guard let presenter = topMostPresenter() else {
                isPresenting = false
                DispatchQueue.main.async {
                    self.parent.request = request
                }
                return
            }
            activeRequest = request
            let picker: UIDocumentPickerViewController
            switch request {
            case .export(let url):
                picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            case .import:
                picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true)
            }
            picker.delegate = self
            picker.allowsMultipleSelection = false
            picker.modalPresentationStyle = .formSheet
            presenter.present(picker, animated: true) {
                self.pendingRequest = nil
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard let request = activeRequest else { return }
            switch request {
            case .export(let url):
                parent.onExportResult(.failure(CocoaError(.userCancelled)))
                _ = url
            case .import:
                parent.onImportResult(.failure(CocoaError(.userCancelled)))
            }
            activeRequest = nil
            isPresenting = false
            DispatchQueue.main.async {
                self.presentIfPossible()
            }
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let request = activeRequest else { return }
            let pickedURL = urls.first
            switch request {
            case .export(let url):
                parent.onExportResult(.success(pickedURL ?? url))
            case .import:
                if let pickedURL {
                    parent.onImportResult(.success(pickedURL))
                } else {
                    parent.onImportResult(.failure(CocoaError(.fileReadNoSuchFile)))
                }
            }
            activeRequest = nil
            isPresenting = false
            DispatchQueue.main.async {
                self.presentIfPossible()
            }
        }

        private func topMostPresenter() -> UIViewController? {
            let root = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .rootViewController
            guard let root else { return nil }
            return topMost(from: root)
        }

        private func topMost(from controller: UIViewController) -> UIViewController {
            var current = controller
            while let presented = current.presentedViewController {
                current = presented
            }
            return current
        }
    }
}
#endif
