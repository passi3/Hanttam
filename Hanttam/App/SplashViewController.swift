//
//  SplashViewController.swift
//  Hanttam
//

import UIKit
import SwiftUI

final class SplashViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let splashView = RippleRingView {
            self.transitionToMain()
        }

        let hostingController = UIHostingController(rootView: splashView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hostingController.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        hostingController.didMove(toParent: self)
    }

    private func transitionToMain() {
        guard let window = view.window else { return }

        let mainTabBar = MainTabBarController()

        UIView.transition(with: window, duration: 0.5) {
            window.rootViewController = mainTabBar
        }
    }
}
