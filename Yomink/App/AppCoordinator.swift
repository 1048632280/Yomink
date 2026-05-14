import UIKit

@MainActor
final class AppCoordinator {
    private let window: UIWindow
    private let environment: AppEnvironment
    private let navigationController = UINavigationController()

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
        navigationController.setViewControllers([bookshelfViewController], animated: false)
        navigationController.navigationBar.prefersLargeTitles = false

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
    }

    func saveApplicationState() {
        environment.readingProgressStore.flushPendingProgress()
    }
}
