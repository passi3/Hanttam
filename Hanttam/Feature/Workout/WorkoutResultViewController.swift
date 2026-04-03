//
//  WorkoutResultViewController.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import UIKit
import SnapKit

// MARK: - ViewController

class WorkoutResultViewController: UIViewController {

    private let data: WorkoutResultDataModel
    private let accentColor: UIColor
    var onDismiss: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()

    init(data: WorkoutResultDataModel) {
        self.data = data
        self.accentColor = RunningLevelManager.shared.accentUIColor
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColor.UI.backgroundGrouped
        setupLayout()
        buildContent()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // MARK: - Layout

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { $0.edges.equalToSuperview() }
        scrollView.alwaysBounceVertical = true

        contentStack.axis = .vertical
        contentStack.spacing = 0
        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(60)
            make.leading.trailing.equalTo(view)
            make.bottom.equalToSuperview().offset(-40)
        }
    }

    // MARK: - Build Content

    private func buildContent() {
        // Header
        addHeader()

        // Summary stats
        addSummaryCard()

        // Spacer
        addSpacer(20)

        // Splits
        if !data.splits.isEmpty {
            addSplitsSection()
        }

        // Spacer
        addSpacer(32)

        // Action buttons
        addActionButtons()

        // Bottom padding
        addSpacer(20)
    }

    // MARK: - Header

    private func addHeader() {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.text = "운동 완료"
        titleLabel.font = AppFont.UI.headlineLG
        titleLabel.textColor = AppColor.UI.textPrimary
        titleLabel.textAlignment = .center
        container.addSubview(titleLabel)

        let checkCircle = UIView()
        checkCircle.backgroundColor = accentColor.withAlphaComponent(0.12)
        checkCircle.layer.cornerRadius = 28
        container.addSubview(checkCircle)

        let checkImage = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)))
        checkImage.tintColor = accentColor
        checkCircle.addSubview(checkImage)

        checkCircle.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
            make.width.height.equalTo(56)
        }
        checkImage.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(checkCircle.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview()
        }

        contentStack.addArrangedSubview(container)
        addSpacer(28)
    }

    // MARK: - Summary Card

    private func addSummaryCard() {
        let card = UIView()
        card.backgroundColor = AppColor.UI.backgroundPrimary
        card.layer.cornerRadius = 16

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 0
        card.addSubview(grid)
        grid.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        }

        // Row 1: Distance | Duration
        let row1 = makeStatRow(
            left: ("거리", formatDistance(data.totalDistance)),
            right: ("시간", formatDuration(data.totalDuration))
        )
        grid.addArrangedSubview(row1)
        grid.addArrangedSubview(makeDivider())

        // Row 2: Avg Pace | Calories (if available)
        let paceStr = formatPace(data.avgPace)
        if let cal = data.calories, cal > 0 {
            let row2 = makeStatRow(
                left: ("평균 페이스", paceStr),
                right: ("칼로리", String(format: "%.0f kcal", cal))
            )
            grid.addArrangedSubview(row2)
        } else {
            let row2 = makeStatRow(
                left: ("평균 페이스", paceStr),
                right: nil
            )
            grid.addArrangedSubview(row2)
        }

        let wrapper = UIView()
        wrapper.addSubview(card)
        card.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
        }

        contentStack.addArrangedSubview(wrapper)
    }

    private func makeStatRow(left: (String, String), right: (String, String)?) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually

        row.addArrangedSubview(makeStatCell(title: left.0, value: left.1))
        if let right {
            row.addArrangedSubview(makeStatCell(title: right.0, value: right.1))
        }

        row.snp.makeConstraints { $0.height.equalTo(72) }
        return row
    }

    private func makeStatCell(title: String, value: String) -> UIView {
        let container = UIView()

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = AppFont.UI.labelMD
        titleLabel.textColor = AppColor.UI.textSecondary

        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = AppFont.UI.metricTitle
        valueLabel.textColor = AppColor.UI.textPrimary
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let stack = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        stack.axis = .vertical
        stack.spacing = 4
        container.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(4)
            make.trailing.equalToSuperview().offset(-4)
            make.centerY.equalToSuperview()
        }
        return container
    }

    private func makeDivider() -> UIView {
        let d = UIView()
        d.backgroundColor = AppColor.UI.separator
        d.snp.makeConstraints { $0.height.equalTo(0.5) }
        return d
    }

    // MARK: - Splits Section

    private func addSplitsSection() {
        // Section header
        let header = UILabel()
        header.text = "km별 페이스"
        header.font = .systemFont(ofSize: 15, weight: .semibold)
        header.textColor = AppColor.UI.textPrimary

        let headerWrapper = UIView()
        headerWrapper.addSubview(header)
        header.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalToSuperview().offset(20)
        }
        contentStack.addArrangedSubview(headerWrapper)
        addSpacer(8)

        // Splits card
        let card = UIView()
        card.backgroundColor = AppColor.UI.backgroundPrimary
        card.layer.cornerRadius = 16

        let splitsStack = UIStackView()
        splitsStack.axis = .vertical
        splitsStack.spacing = 0
        card.addSubview(splitsStack)
        splitsStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // Find pace range for bar width
        let paces = data.splits.map(\.pace)
        let maxPace = paces.max() ?? 1
        let minPace = paces.min() ?? 1

        for (i, split) in data.splits.enumerated() {
            let row = makeSplitRow(split: split, minPace: minPace, maxPace: maxPace)
            splitsStack.addArrangedSubview(row)
            if i < data.splits.count - 1 {
                let divider = UIView()
                divider.backgroundColor = AppColor.UI.separator
                splitsStack.addArrangedSubview(divider)
                divider.snp.makeConstraints { $0.height.equalTo(0.5) }
            }
        }

        let wrapper = UIView()
        wrapper.addSubview(card)
        card.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
        }
        contentStack.addArrangedSubview(wrapper)
    }

    private func makeSplitRow(split: WorkoutResultDataModel.SplitData, minPace: TimeInterval, maxPace: TimeInterval) -> UIView {
        let container = UIView()
        container.snp.makeConstraints { $0.height.equalTo(44) }

        // Km label
        let kmLabel = UILabel()
        let isPartial = split.distance < 1000
        kmLabel.text = isPartial ? String(format: "%.1fkm", split.distance / 1000) : "\(split.km)km"
        kmLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        kmLabel.textColor = AppColor.UI.textSecondary
        kmLabel.textAlignment = .right
        container.addSubview(kmLabel)
        kmLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(48)
        }

        // Pace bar
        let barBg = UIView()
        barBg.backgroundColor = AppColor.UI.separator.withAlphaComponent(0.2)
        barBg.layer.cornerRadius = 3
        container.addSubview(barBg)
        barBg.snp.makeConstraints { make in
            make.leading.equalTo(kmLabel.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.height.equalTo(6)
            make.trailing.equalToSuperview().offset(-90)
        }

        let bar = UIView()
        bar.layer.cornerRadius = 3
        // Color: faster = accent, slower = orange/red tint
        let normalizedPace: CGFloat
        if maxPace > minPace {
            normalizedPace = CGFloat((split.pace - minPace) / (maxPace - minPace))
        } else {
            normalizedPace = 0
        }
        bar.backgroundColor = interpolateColor(from: accentColor, to: AppColor.UI.workoutPause, fraction: normalizedPace)
        barBg.addSubview(bar)

        // Bar width relative to max pace
        let barRatio = maxPace > 0 ? CGFloat(split.pace / maxPace) : 1.0
        bar.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(max(0.15, min(1.0, barRatio)))
        }

        // Pace text
        let paceLabel = UILabel()
        paceLabel.text = formatPace(split.pace)
        paceLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        paceLabel.textColor = AppColor.UI.textPrimary
        paceLabel.textAlignment = .right
        container.addSubview(paceLabel)
        paceLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().offset(-16)
            make.centerY.equalToSuperview()
            make.width.equalTo(70)
        }

        return container
    }

    // MARK: - Action Buttons

    private func addActionButtons() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10

        if data.alreadySaved {
            // 이미 저장된 경우 (인터벌) — 완료 버튼만 표시
            let doneBtn = UIButton(type: .system)
            doneBtn.setTitle("완료", for: .normal)
            doneBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            doneBtn.setTitleColor(.white, for: .normal)
            doneBtn.backgroundColor = accentColor
            doneBtn.layer.cornerRadius = 14
            doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
            doneBtn.snp.makeConstraints { $0.height.equalTo(50) }
            stack.addArrangedSubview(doneBtn)
        } else {
            // 저장 버튼
            let saveBtn = UIButton(type: .system)
            saveBtn.setTitle("운동 저장", for: .normal)
            saveBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            saveBtn.setTitleColor(.white, for: .normal)
            saveBtn.backgroundColor = accentColor
            saveBtn.layer.cornerRadius = 14
            saveBtn.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
            saveBtn.snp.makeConstraints { $0.height.equalTo(50) }
            stack.addArrangedSubview(saveBtn)

            // 삭제 버튼
            let discardBtn = UIButton(type: .system)
            discardBtn.setTitle("운동 삭제", for: .normal)
            discardBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            discardBtn.setTitleColor(.systemRed, for: .normal)
            discardBtn.backgroundColor = AppColor.UI.backgroundPrimary
            discardBtn.layer.cornerRadius = 14
            discardBtn.addTarget(self, action: #selector(discardTapped), for: .touchUpInside)
            discardBtn.snp.makeConstraints { $0.height.equalTo(50) }
            stack.addArrangedSubview(discardBtn)
        }

        let wrapper = UIView()
        wrapper.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
        }
        contentStack.addArrangedSubview(wrapper)
    }

    @objc private func saveTapped() {
        // 저장 중 UI 피드백
        view.isUserInteractionEnabled = false

        HealthKitStore.shared.saveRunningWorkout(
            start: data.startDate,
            end: data.endDate,
            distance: data.totalDistance,
            calories: data.calories,
            routeLocations: data.routeLocations,
            isIndoor: data.isIndoor
        ) { [weak self] success, error in
            guard let self else { return }
            self.view.isUserInteractionEnabled = true

            if success {
                self.showAlert(title: "저장 완료", message: "운동이 건강 앱에 저장되었습니다.") {
                    self.dismiss(animated: true) { self.onDismiss?() }
                }
            } else {
                self.showAlert(title: "저장 실패", message: error?.localizedDescription ?? "다시 시도해주세요.")
            }
        }
    }

    @objc private func doneTapped() {
        dismiss(animated: true) { [weak self] in self?.onDismiss?() }
    }

    @objc private func discardTapped() {
        let alert = UIAlertController(title: "운동 삭제", message: "이 운동 데이터를 삭제하시겠습니까?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
            self?.dismiss(animated: true) { self?.onDismiss?() }
        })
        present(alert, animated: true)
    }

    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completion?() })
        present(alert, animated: true)
    }

    // MARK: - Helpers

    private func addSpacer(_ height: CGFloat) {
        let spacer = UIView()
        spacer.snp.makeConstraints { $0.height.equalTo(height) }
        contentStack.addArrangedSubview(spacer)
    }

    private func formatDistance(_ meters: Double) -> String {
        String(format: "%.2f km", meters / 1000)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = Int(seconds) % 3600 / 60
        let s = Int(seconds) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func formatPace(_ secPerKm: TimeInterval?) -> String {
        guard let p = secPerKm, p.isFinite, p > 0, p < 3600 else { return "--'--\"" }
        return String(format: "%d'%02d\"", Int(p) / 60, Int(p) % 60)
    }

    private func interpolateColor(from: UIColor, to: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = max(0, min(1, fraction))
        return UIColor(
            red: r1 + (r2 - r1) * f,
            green: g1 + (g2 - g1) * f,
            blue: b1 + (b2 - b1) * f,
            alpha: 1
        )
    }
}
