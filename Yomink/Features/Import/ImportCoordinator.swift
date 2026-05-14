import UIKit
import UniformTypeIdentifiers

@MainActor
final class ImportCoordinator {
    func makeImportController() -> UIViewController {
        UIDocumentPickerViewController(forOpeningContentTypes: [.plainText], asCopy: true)
    }
}
