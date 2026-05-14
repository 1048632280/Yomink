import UIKit
import UniformTypeIdentifiers

@MainActor
final class ImportCoordinator: NSObject, UIDocumentPickerDelegate {
    var onPickedDocument: ((URL) -> Void)?

    func makeImportController() -> UIViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.plainText], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        return picker
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else {
            return
        }
        onPickedDocument?(url)
    }
}
