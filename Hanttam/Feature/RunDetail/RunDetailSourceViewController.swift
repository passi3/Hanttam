//
//  RunDetailSourceViewController.swift
//  Hanttam
//

import UIKit
import SwiftUI
import SnapKit

class RunDetailSourceViewController: UIViewController {
    private let record: RunningRecord

    init(record: RunningRecord) {
        self.record = record
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.UI.backgroundGrouped

        let sourceView = RunDetailSourceView(record: record)
        let hosting = UIHostingController(rootView: sourceView)
        hosting.view.backgroundColor = .clear
        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.snp.makeConstraints { make in make.edges.equalToSuperview() }
        hosting.didMove(toParent: self)
    }
}
