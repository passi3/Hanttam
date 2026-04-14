//
//  SlideHorizontalAnimator.swift
//  Hanttam
//

import UIKit

final class SlideHorizontalAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isDismiss: Bool
    init(isDismiss: Bool) { self.isDismiss = isDismiss }

    func transitionDuration(using ctx: UIViewControllerContextTransitioning?) -> TimeInterval { 0.28 }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        let container = ctx.containerView
        let width = container.bounds.width

        if isDismiss {
            guard let from = ctx.view(forKey: .from) else { return }
            if let to = ctx.view(forKey: .to) {
                to.frame = container.bounds
                container.insertSubview(to, belowSubview: from)
            }
            UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0, options: .curveEaseInOut) {
                from.frame.origin.x = width
            } completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        } else {
            guard let to = ctx.view(forKey: .to) else { return }
            to.frame = container.bounds.offsetBy(dx: width, dy: 0)
            container.addSubview(to)
            UIView.animate(withDuration: transitionDuration(using: ctx), delay: 0, options: .curveEaseInOut) {
                to.frame.origin.x = 0
            } completion: { _ in
                ctx.completeTransition(!ctx.transitionWasCancelled)
            }
        }
    }
}
