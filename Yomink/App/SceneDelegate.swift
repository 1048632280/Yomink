import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var coordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else {
            return
        }

        let window = UIWindow(windowScene: windowScene)
        let environment = AppEnvironment.makeDefault()
        let coordinator = AppCoordinator(window: window, environment: environment)
        self.window = window
        self.coordinator = coordinator
        coordinator.start()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        coordinator?.saveApplicationState()
    }
}
