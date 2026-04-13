//
//  SplashViewController.swift
//  Hanttam
//

import UIKit
import SwiftUI

final class SplashViewController: UIViewController {

    private let logoSize: CGFloat = 350
    private let splashDuration: TimeInterval = 1.4
    private var hasScheduledTransition = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let splashLogo = SplashGlitchLogoView(size: logoSize)
        let hostingController = UIHostingController(rootView: splashLogo)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hostingController.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            hostingController.view.widthAnchor.constraint(equalToConstant: logoSize),
            hostingController.view.heightAnchor.constraint(equalToConstant: logoSize),
        ])

        hostingController.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleTransitionToMain()
    }

    private func scheduleTransitionToMain() {
        guard !hasScheduledTransition else { return }
        hasScheduledTransition = true

        DispatchQueue.main.asyncAfter(deadline: .now() + splashDuration) { [weak self] in
            self?.transitionToMain()
        }
    }

    private func transitionToMain() {
        guard let window = view.window else { return }

        let mainTabBar = MainTabBarController()

        UIView.transition(with: window, duration: 0.5) {
            window.rootViewController = mainTabBar
        }
    }
}

private struct SplashGlitchLogoView: View {
    let size: CGFloat

    @State private var redOffset: CGFloat = 0
    @State private var blueOffset: CGFloat = 0
    @State private var verticalJitter: CGFloat = 0
    @State private var sliceOffset: CGFloat = 0
    @State private var glitchOpacity: Double = 0

    var body: some View {
        ZStack {
            HanttamBrandLogo()

            glitchLayer(color: .red, xOffset: redOffset)
            glitchLayer(color: .cyan, xOffset: blueOffset)
        }
        .frame(width: size, height: size)
        .drawingGroup()
        .onAppear(perform: startGlitchSequence)
    }

    private func glitchLayer(color: Color, xOffset: CGFloat) -> some View {
        HanttamBrandLogo(color: color.opacity(glitchOpacity))
            .offset(x: xOffset, y: verticalJitter)
            .mask(sliceMask)
            .blendMode(.screen)
    }

    private var sliceMask: some View {
        ZStack {
            Rectangle()
                .frame(height: size * 0.075)
                .offset(y: sliceOffset - size * 0.23)
            Rectangle()
                .frame(height: size * 0.045)
                .offset(y: -sliceOffset * 0.35)
            Rectangle()
                .frame(height: size * 0.06)
                .offset(y: sliceOffset + size * 0.18)
        }
        .frame(width: size, height: size)
    }

    private func startGlitchSequence() {
        runGlitchBurst()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            runGlitchBurst()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            runGlitchBurst()
        }
    }

    private func runGlitchBurst() {
        let duration = 0.045
        let steps = 8
        let maxOffset = max(size * 0.035, 8)

        for step in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * duration) {
                withAnimation(.easeInOut(duration: duration)) {
                    redOffset = CGFloat.random(in: -maxOffset...(-maxOffset * 0.2))
                    blueOffset = CGFloat.random(in: (maxOffset * 0.2)...maxOffset)
                    verticalJitter = CGFloat.random(in: -2...2)
                    sliceOffset = CGFloat.random(in: -(size * 0.2)...(size * 0.2))
                    glitchOpacity = Double.random(in: 0.45...0.75)
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Double(steps) * duration) {
            resetGlitch()
        }
    }

    private func resetGlitch() {
        withAnimation(.easeOut(duration: 0.08)) {
            redOffset = 0
            blueOffset = 0
            verticalJitter = 0
            sliceOffset = 0
            glitchOpacity = 0
        }
    }
}
