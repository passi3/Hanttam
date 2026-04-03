//
//  RunningLevelViewController.swift
//  Hanttam
//
//  Created by passi on 3/30/26.
//

import UIKit
import RxCocoa
import RxSwift
import SnapKit

final class RunningLevelViewController: HTViewController {
    
    private let viewModel          = RunningLevelViewModel()
    private let viewDidLoadSubject = PublishSubject<Void>()
    private let disposeBag         = DisposeBag()
    
    private let scrollView = UIScrollView()
    private let stackView  = UIStackView()
    
    // 현재 레벨 카드
    private let levelIconView  = UIImageView()
    private let levelIconBg    = UIView()
    private let levelNameLabel = UILabel()
    private let totalDistLabel = UILabel()
    
    // 진행도
    private let progressContainer   = UIView()
    private let nextLevelLabel      = UILabel()
    private let remainingLabel      = UILabel()
    private let progressTrack       = UIView()
    private let progressFill        = UIView()
    private let thresholdStartLabel = UILabel()
    private let thresholdEndLabel   = UILabel()
    private var progressFillWidthConstraint: Constraint?
    
    // 레벨 목록
    private let levelListStack = UIStackView()
    
    //MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
        viewDidLoadSubject.onNext(())
    }
    
    private func bind() {
        let input = RunningLevelViewModel.Input(
            viewDidLoad: viewDidLoadSubject.asObservable()
        )
        let output = viewModel.transform(input: input)

        output.level
            .drive(onNext: { [weak self] level in
                self?.updateLevelCard(level)
            })
            .disposed(by: disposeBag)

        output.totalDistanceKm
            .drive(onNext: { [weak self] km in
                self?.totalDistLabel.text = String(format: "%.1f km", km)
            })
            .disposed(by: disposeBag)

        Driver.combineLatest(output.progress, output.remainingKm, output.level)
            .drive(onNext: { [weak self] progress, remaining, level in
                self?.updateProgress(progress: progress, remaining: remaining, level: level)
            })
            .disposed(by: disposeBag)

        output.levelItems
            .drive(onNext: { [weak self] items in
                self?.updateLevelList(items)
            })
            .disposed(by: disposeBag)
    }
    
    //MARK: - Config
    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
    }
    override func configLayout() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        stackView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(20)
            make.leading.trailing.equalTo(view).inset(20)
            make.bottom.equalToSuperview().offset(-40)
        }
        
        stackView.addArrangedSubview(buildLevelCard())
        stackView.addArrangedSubview(buildProgressSection())
        stackView.addArrangedSubview(buildLevelListSection())
    }
    override func configView() {
        view.backgroundColor = AppColor.UI.backgroundGrouped
        stackView.axis    = .vertical
        stackView.spacing = 32
    }
    
    //MARK: - Level Card
    
    private func buildLevelCard() -> UIView {
        let card = UIView()
        card.backgroundColor = AppColor.UI.backgroundPrimary
        card.layer.cornerRadius = 16

        // 아이콘 배경
        levelIconBg.layer.cornerRadius = 60
        card.addSubview(levelIconBg)

        // 아이콘 테두리
        let iconBorder = UIView()
        iconBorder.layer.cornerRadius = 60
        iconBorder.layer.borderWidth = 2
        iconBorder.layer.borderColor = AppColor.UI.yellow.withAlphaComponent(0.3).cgColor
        card.addSubview(iconBorder)

        levelIconView.contentMode = .scaleAspectFit
        levelIconView.tintColor = AppColor.UI.yellow
        card.addSubview(levelIconView)

        levelNameLabel.font = .monospacedSystemFont(ofSize: 32, weight: .bold)
        levelNameLabel.textAlignment = .center
        card.addSubview(levelNameLabel)

        totalDistLabel.font = .monospacedSystemFont(ofSize: 22, weight: .ultraLight)
        totalDistLabel.textColor = AppColor.UI.textPrimary
        totalDistLabel.textAlignment = .center
        card.addSubview(totalDistLabel)

        card.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(280)
        }

        levelIconBg.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(40)
            make.width.height.equalTo(120)
        }

        iconBorder.snp.makeConstraints { make in
            make.center.equalTo(levelIconBg)
            make.width.height.equalTo(120)
        }

        levelIconView.snp.makeConstraints { make in
            make.center.equalTo(levelIconBg)
            make.width.height.equalTo(48)
        }

        levelNameLabel.snp.makeConstraints { make in
            make.top.equalTo(levelIconBg.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(16)
        }
        
        totalDistLabel.snp.makeConstraints { make in
            make.top.equalTo(levelNameLabel.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().offset(-40)
        }

        return card
    }
    
    private func updateLevelCard(_ level: UserRunningLevel) {
        let color = level.gradeColor

        levelIconBg.backgroundColor = color.withAlphaComponent(0.15)
        levelIconView.image = UIImage(systemName: level.iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 48, weight: .light))
        levelIconView.tintColor = color

        // 테두리 업데이트
        if let border = levelIconBg.superview?.subviews.first(where: { $0 != levelIconBg && $0 != levelIconView && $0.layer.cornerRadius == 60 }) {
            border.layer.borderColor = color.withAlphaComponent(0.3).cgColor
        }

        levelNameLabel.text = level.displayName
        levelNameLabel.textColor = color
    }
    
    private func buildProgressSection() -> UIView {
        progressContainer.backgroundColor = AppColor.UI.backgroundPrimary
        progressContainer.layer.cornerRadius = 12

        let topRow = UIStackView(arrangedSubviews: [nextLevelLabel, remainingLabel])
        topRow.axis = .horizontal
        topRow.distribution = .equalSpacing

        nextLevelLabel.text = "다음 레벨까지"
        nextLevelLabel.font = .systemFont(ofSize: 12, weight: .light)
        nextLevelLabel.textColor = AppColor.UI.textSecondary

        remainingLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)

        progressTrack.backgroundColor = AppColor.UI.systemGray5
        progressTrack.layer.cornerRadius = 4

        progressFill.layer.cornerRadius = 4
        progressTrack.addSubview(progressFill)

        let bottomRow = UIStackView(arrangedSubviews: [thresholdStartLabel, thresholdEndLabel])
        bottomRow.axis = .horizontal
        bottomRow.distribution = .equalSpacing

        thresholdStartLabel.font = .monospacedSystemFont(ofSize: 10, weight: .light)
        thresholdStartLabel.textColor = AppColor.UI.textTertiary
        thresholdEndLabel.font = .monospacedSystemFont(ofSize: 10, weight: .light)
        thresholdEndLabel.textColor = AppColor.UI.textTertiary

        progressContainer.addSubview(topRow)
        progressContainer.addSubview(progressTrack)
        progressContainer.addSubview(bottomRow)

        topRow.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(20)
            make.leading.trailing.equalToSuperview().inset(20)
        }

        progressTrack.snp.makeConstraints { make in
            make.top.equalTo(topRow.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(8)
        }

        progressFill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            self.progressFillWidthConstraint = make.width.equalTo(0).constraint
        }

        bottomRow.snp.makeConstraints { make in
            make.top.equalTo(progressTrack.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().offset(-20)
        }

        return progressContainer
    }
    
    private func updateProgress(progress: Double, remaining: Double, level: UserRunningLevel) {
        let color = level.gradeColor
        remainingLabel.text = String(format: "%.1f km 남음", remaining)
        remainingLabel.textColor = color
        progressFill.backgroundColor = color

        thresholdStartLabel.text = String(format: "%.0f km", level.threshold)
        if let next = level.nextThreshold {
            thresholdEndLabel.text = String(format: "%.0f km", next)
        } else {
            nextLevelLabel.text = "최고 레벨 달성!"
            nextLevelLabel.textColor = color
            remainingLabel.isHidden = true
            thresholdStartLabel.isHidden = true
            thresholdEndLabel.isHidden = true
        }

        view.layoutIfNeeded()
        let trackWidth = progressTrack.bounds.width
        progressFillWidthConstraint?.update(offset: trackWidth * progress)
        
        UIView.animate(withDuration: 1.0, delay: 0.3, options: .curveEaseOut) {
            self.view.layoutIfNeeded()
        }
    }
    
    //MARK: - Level List
    
    private func buildLevelListSection() -> UIView {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.text = "레벨 시스템"
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = AppColor.UI.textSecondary

        levelListStack.axis = .vertical
        levelListStack.spacing = 8

        container.addSubview(titleLabel)
        container.addSubview(levelListStack)

        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview()
        }

        levelListStack.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(16)
            make.leading.trailing.bottom.equalToSuperview()
        }

        return container
    }
    
    private func updateLevelList(_ items: [RunningLevelViewModel.LevelItem]) {
        levelListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for item in items {
            levelListStack.addArrangedSubview(buildLevelRow(item))
        }
    }

    private func buildLevelRow(_ item: RunningLevelViewModel.LevelItem) -> UIView {
        let row = UIView()
        row.backgroundColor = AppColor.UI.backgroundPrimary
        row.layer.cornerRadius = 12
        if item.isCurrent {
            row.layer.borderWidth = 1
            row.layer.borderColor = item.level.gradeColor.withAlphaComponent(0.3).cgColor
        }

        let color = item.level.gradeColor
        let dimColor = UIColor.systemGray4

        // 아이콘
        let iconBg = UIView()
        iconBg.backgroundColor = item.isAchieved ? color.withAlphaComponent(0.15) : dimColor.withAlphaComponent(0.1)
        iconBg.layer.cornerRadius = 20
        row.addSubview(iconBg)

        let icon = UIImageView(image: UIImage(systemName: item.level.iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .light)))
        icon.tintColor = item.isAchieved ? color : dimColor
        iconBg.addSubview(icon)

        // 이름
        let nameLabel = UILabel()
        nameLabel.text = item.level.displayName
        nameLabel.font = .monospacedSystemFont(ofSize: 15, weight: item.isCurrent ? .bold : .regular)
        nameLabel.textColor = item.isAchieved ? AppColor.UI.textPrimary : dimColor

        // 거리
        let distLabel = UILabel()
        distLabel.text = String(format: "%.0f km+", item.level.threshold)
        distLabel.font = .monospacedSystemFont(ofSize: 11, weight: .light)
        distLabel.textColor = item.isAchieved
            ? AppColor.UI.textSecondary
            : dimColor.withAlphaComponent(0.5)

        let textStack = UIStackView(arrangedSubviews: [nameLabel, distLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        row.addSubview(textStack)

        iconBg.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(14)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(40)
        }

        icon.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        textStack.snp.makeConstraints { make in
            make.leading.equalTo(iconBg.snp.trailing).offset(14)
            make.centerY.equalToSuperview()
        }

        row.snp.makeConstraints { make in
            make.height.equalTo(68)
        }

        // 우측 배지
        if item.isCurrent {
            let badge = PaddedLabel()
            badge.text = "현재"
            badge.font = .systemFont(ofSize: 11, weight: .bold)
            badge.textColor = color
            badge.backgroundColor = color.withAlphaComponent(0.15)
            badge.layer.cornerRadius = 12
            badge.clipsToBounds = true
            row.addSubview(badge)
            badge.snp.makeConstraints { make in
                make.trailing.equalToSuperview().offset(-14)
                make.centerY.equalToSuperview()
                make.height.equalTo(24)
            }
        } else if item.isAchieved {
            let check = UIImageView(image: UIImage(systemName: "checkmark")?
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)))
            check.tintColor = color
            row.addSubview(check)
            check.snp.makeConstraints { make in
                make.trailing.equalToSuperview().offset(-14)
                make.centerY.equalToSuperview()
            }
        }

        return row
    }
}

// MARK: - Padded Label

private class PaddedLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + 20, height: size.height + 8)
    }
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 10, dy: 4))
    }
}

