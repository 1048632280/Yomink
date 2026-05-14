import UIKit

@MainActor
final class AppCoordinator {
    private let window: UIWindow
    private let environment: AppEnvironment
    private let navigationController = UINavigationController()
    private let importCoordinator = ImportCoordinator()
    private weak var bookshelfViewController: BookshelfViewController?

    init(window: UIWindow, environment: AppEnvironment) {
        self.window = window
        self.environment = environment
    }

    func start() {
        let viewModel = BookshelfViewModel(
            bookRepository: environment.bookRepository,
            appSettingsStore: environment.appSettingsStore
        )
        let bookshelfViewController = BookshelfViewController(viewModel: viewModel)
        bookshelfViewController.onImportRequested = { [weak self] in
            self?.presentImportPicker()
        }
        bookshelfViewController.onBookSelected = { [weak self] book in
            self?.openReader(book)
        }
        importCoordinator.onPickedDocument = { [weak self] url in
            self?.importBook(from: url)
        }
        self.bookshelfViewController = bookshelfViewController

        navigationController.setViewControllers([bookshelfViewController], animated: false)
        navigationController.navigationBar.prefersLargeTitles = false

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
    }

    func saveApplicationState() {
        environment.readingProgressStore.flushPendingProgress()
    }

    private func presentImportPicker() {
        let picker = importCoordinator.makeImportController()
        navigationController.present(picker, animated: true)
    }

    private func importBook(from url: URL) {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let book = try await environment.bookImportService.importBook(from: url)
                bookshelfViewController?.refreshBooks()
                openReader(book)
            } catch {
                presentError(
                    title: "\u{5BFC}\u{5165}\u{5931}\u{8D25}",
                    message: "\u{65E0}\u{6CD5}\u{5BFC}\u{5165}\u{8FD9}\u{4E2A} TXT \u{6587}\u{4EF6}\u{3002}"
                )
            }
        }
    }

    private func openReader(_ book: BookRecord) {
        let readerViewController = ReaderViewController(
            book: book,
            openingService: environment.readerOpeningService,
            pagingService: environment.readerPagingService,
            readingSettingsStore: environment.readingSettingsStore,
            progressStore: environment.readingProgressStore
        )
        navigationController.pushViewController(readerViewController, animated: true)
    }

    private func presentError(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "\u{597D}", style: .default))
        navigationController.present(alert, animated: true)
    }
}
