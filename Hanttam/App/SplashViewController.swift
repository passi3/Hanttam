//
//  SplashViewController.swift
//  Hanttam
//

import UIKit
import SwiftUI
import RxSwift
import RxCocoa

final class SplashViewController: HTViewController {

    private let logoSize: CGFloat = 350
    private let viewModel = SplashViewModel()
    private let viewDidAppearSubject = PublishSubject<Void>()
    private let disposeBag = DisposeBag()

    override func configHierarchy() {
        view.backgroundColor = .white

        let splashLogo = SplashGlitchLogoView(size: logoSize)
        let host = UIHostingController(rootView: splashLogo)
        host.view.backgroundColor = .clear

        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            host.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            host.view.widthAnchor.constraint(equalToConstant: logoSize),
            host.view.heightAnchor.constraint(equalToConstant: logoSize),
        ])
        host.didMove(toParent: self)
    }

    override func setupBindings() {
        let output = viewModel.transform(
            input: SplashViewModel.Input(viewDidAppear: viewDidAppearSubject.asObservable())
        )
        output.transitionToMain
            .emit(onNext: { [weak self] in self?.transitionToMain() })
            .disposed(by: disposeBag)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearSubject.onNext(())
    }

    private func transitionToMain() {
        guard let window = view.window else { return }
        UIView.transition(with: window, duration: 0.5) {
            window.rootViewController = MainTabBarController()
        }
    }
}
