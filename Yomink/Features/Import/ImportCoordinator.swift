import UIKit
import UniformTypeIdentifiers

final class ImportCoordinator {
    func makeImportController() -> UIViewController {
        UIDocumentPickerViewController(forOpeningContentTypes: [.plainText], asCopy: true)
    }
}
