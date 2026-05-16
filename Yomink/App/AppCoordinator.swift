import UIKit

@MainActor
final class AppCoordinator {
    private let window: UIWindow
    private let environment: AppEnvironment
    private let navigationController = YominkNavigationController()
    private let importCoordinator = ImportCoordinator()
    private weak var bookshelfViewController: BookshelfViewController?

    init(window: UIWindow, environment: AppEnvironment) {
        self.window = window
        self.environment = environment
    }

    func start() {
        let viewModel = BookshelfViewModel(
            bookRepository: environment.bookRepository,
            groupRepository: environment.bookGroupRepository,
            appSettingsStore: environment.appSettingsStore,
            deletionService: BookDeletionService(
                bookRepository: environment.bookRepository,
                searchIndexService: environment.searchIndexService,
                pagingService: environment.readerPagingService
            )
        )
        let bookshelfViewController = BookshelfViewController(viewModel: viewModel)
        bookshelfViewController.onImportRequested = { [weak self] in
            self?.presentImportPicker()
        }
        bookshelfViewController.onBookSelected = { [weak self] book in
            self?.openReader(book)
        }
        bookshelfViewController.onAppSettingsRequested = { [weak self] in
            self?.showAppSettings()
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
            } catch BookImportError.duplicateBook(let duplicate) {
                presentDuplicateImportAlert(duplicate: duplicate, sourceURL: url)
            } catch {
                presentError(
                    title: "\u{5BFC}\u{5165}\u{5931}\u{8D25}",
                    message: "\u{65E0}\u{6CD5}\u{5BFC}\u{5165}\u{8FD9}\u{4E2A} TXT \u{6587}\u{4EF6}\u{3002}"
                )
            }
        }
    }

    private func presentDuplicateImportAlert(duplicate: BookImportDuplicate, sourceURL: URL) {
        let alert = UIAlertController(
            title: "\u{4E66}\u{7C4D}\u{5DF2}\u{5B58}\u{5728}",
            message: "\u{300A}\(duplicate.existingBook.title)\u{300B}\u{5DF2}\u{5728}\u{4E66}\u{67B6}\u{4E2D}\u{3002}\u{53EF}\u{4EE5}\u{521B}\u{5EFA}\u{300A}\(duplicate.copyTitle)\u{300B}\u{FF0C}\u{6216}\u{53D6}\u{6D88}\u{5BFC}\u{5165}\u{3002}",
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: "\u{53D6}\u{6D88}\u{5BFC}\u{5165}", style: .cancel)
        )
        alert.addAction(
            UIAlertAction(title: "\u{521B}\u{5EFA}\u{526F}\u{672C}", style: .default) { [weak self] _ in
                self?.importDuplicateBookCopy(from: sourceURL)
            }
        )
        navigationController.present(alert, animated: true)
    }

    private func importDuplicateBookCopy(from url: URL) {
        Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let book = try await environment.bookImportService.importBook(
                    from: url,
                    duplicateResolution: .createCopy
                )
                bookshelfViewController?.refreshBooks()
                openReader(book)
            } catch {
                presentError(
                    title: "\u{5BFC}\u{5165}\u{5931}\u{8D25}",
                    message: "\u{65E0}\u{6CD5}\u{521B}\u{5EFA}\u{8FD9}\u{672C}\u{4E66}\u{7684}\u{526F}\u{672C}\u{3002}"
                )
            }
        }
    }

    private func openReader(_ book: BookRecord) {
        let readerViewController = ReaderViewController(
            book: book,
            openingService: environment.readerOpeningService,
            pagingService: environment.readerPagingService,
            bookmarkService: environment.readingBookmarkService,
            chapterService: environment.readingChapterService,
            searchIndexService: environment.searchIndexService,
            contentFilterService: environment.contentFilterService,
            bookDetailService: environment.bookDetailService,
            tapAreaSettingsStore: environment.tapAreaSettingsStore,
            readingSettingsStore: environment.readingSettingsStore,
            progressStore: environment.readingProgressStore
        )
        navigationController.pushViewController(readerViewController, animated: true)
    }

    private func showAppSettings() {
        let viewController = AppSettingsViewController(appSettingsStore: environment.appSettingsStore)
        viewController.onSettingsChanged = { [weak self] in
            self?.bookshelfViewController?.refreshBooks()
        }
        navigationController.pushViewController(viewController, animated: true)
    }

    private func presentError(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "\u{597D}", style: .default))
        navigationController.present(alert, animated: true)
    }
}

private final class YominkNavigationController: UINavigationController {
    override var childForHomeIndicatorAutoHidden: UIViewController? {
        topViewController
    }

    override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
        topViewController
    }

    override var childForStatusBarHidden: UIViewController? {
        topViewController
    }
}
