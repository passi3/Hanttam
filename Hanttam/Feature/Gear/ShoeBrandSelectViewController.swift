//
//  ShoeBrandSelectViewController.swift
//  Hanttam
//
//  Created by passi on 4/10/26.
//

import UIKit
import SnapKit

enum ShoeBrand: String, CaseIterable {
    case adidas = "Adidas"
    case asics = "ASICS"
    case brooks = "Brooks"
    case hoka = "HOKA"
    case newBalance = "New Balance"
    case nike = "NIKE"
    case on = "On"
    case puma = "PUMA"
    case salomon = "Salomon"
    case saucony = "Saucony"
    case liNing = "LI-NING"

    var displayName: String { rawValue }

    /// Keyword used to query `brand_name` in Supabase.
    var searchKeyword: String { rawValue }
}

final class ShoeBrandSelectViewController: HTViewController {
    private let onRegistered: ((RegisteredShoe) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let gridStack = UIStackView()
    private let separator = UIView()
    private let manualRegisterButton = UIButton(type: .system)

    private let brands = ShoeBrand.allCases
    private let columnCount = 3
    private let tileHeight: CGFloat = 84
    private let tileSpacing: CGFloat = 12

    init(onRegistered: ((RegisteredShoe) -> Void)? = nil) {
        self.onRegistered = onRegistered
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        contentStack.addArrangedSubview(gridStack)
        contentStack.addArrangedSubview(separator)
        contentStack.addArrangedSubview(manualRegisterButton)
    }

    override func configLayout() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 20, left: 20, bottom: 24, right: 20))
            make.width.equalTo(scrollView.snp.width).offset(-40)
        }
        separator.snp.makeConstraints { make in
            make.height.equalTo(1)
        }
        manualRegisterButton.snp.makeConstraints { make in
            make.height.equalTo(54)
        }
    }

    override func configView() {
        title = "장비"
        view.backgroundColor = AppColor.UI.backgroundGrouped

        scrollView.alwaysBounceVertical = true

        contentStack.axis = .vertical
        contentStack.spacing = 20
        contentStack.alignment = .fill

        gridStack.axis = .vertical
        gridStack.spacing = tileSpacing
        gridStack.alignment = .fill
        gridStack.distribution = .fill

        separator.backgroundColor = AppColor.UI.border

        manualRegisterButton.setTitle("직접 등록", for: .normal)
        manualRegisterButton.titleLabel?.font = AppFont.UI.buttonMD
        manualRegisterButton.setTitleColor(AppColor.UI.textPrimary, for: .normal)
        manualRegisterButton.backgroundColor = AppColor.UI.cardBackground
        manualRegisterButton.layer.cornerRadius = 16
        manualRegisterButton.layer.borderWidth = 1
        manualRegisterButton.layer.borderColor = AppColor.UI.border.cgColor
        manualRegisterButton.addTarget(self, action: #selector(manualRegisterTapped), for: .touchUpInside)

        buildBrandGrid()
    }

    private func buildBrandGrid() {
        var chunks: [[(Int, ShoeBrand)]] = []
        for (index, brand) in brands.enumerated() {
            if let last = chunks.last, last.count < columnCount {
                chunks[chunks.count - 1].append((index, brand))
            } else {
                chunks.append([(index, brand)])
            }
        }

        for row in chunks {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = tileSpacing
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually

            for (index, brand) in row {
                let button = makeBrandButton(title: brand.displayName, tag: index)
                rowStack.addArrangedSubview(button)
            }

            // Pad the last row with invisible spacers so items stay in a grid.
            if row.count < columnCount {
                for _ in 0..<(columnCount - row.count) {
                    let spacer = UIView()
                    spacer.isUserInteractionEnabled = false
                    rowStack.addArrangedSubview(spacer)
                }
            }

            rowStack.snp.makeConstraints { make in
                make.height.equalTo(tileHeight)
            }
            gridStack.addArrangedSubview(rowStack)
        }
    }

    private func makeBrandButton(title: String, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = tag
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = AppFont.UI.titleMD
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.setTitleColor(AppColor.UI.textPrimary, for: .normal)
        button.backgroundColor = AppColor.UI.cardBackground
        button.layer.cornerRadius = 16
        button.layer.borderWidth = 1
        button.layer.borderColor = AppColor.UI.border.cgColor
        button.addTarget(self, action: #selector(brandTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func brandTapped(_ sender: UIButton) {
        guard brands.indices.contains(sender.tag) else { return }
        let brand = brands[sender.tag]
        let viewController = ShoeSearchViewController(
            brand: brand,
            onRegistered: onRegistered
        )
        navigationController?.pushViewController(viewController, animated: true)
    }

    @objc private func manualRegisterTapped() {
        let viewController = RegisterShoeViewController(
            mode: .manual,
            onRegistered: onRegistered
        )
        navigationController?.pushViewController(viewController, animated: true)
    }
}
