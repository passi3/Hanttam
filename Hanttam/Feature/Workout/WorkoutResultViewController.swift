//
//  WorkoutResultViewController.swift
//  Hanttam
//
//  Created by passi on 4/1/26.
//

import UIKit
import MapKit
import SnapKit

final class WorkoutResultViewController: UIViewController {

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

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { $0.edges.equalToSuperview() }
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false

        contentStack.axis = .vertical
        contentStack.spacing = 18
        scrollView.addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide).inset(UIEdgeInsets(top: 18, left: 18, bottom: 30, right: 18))
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-36)
        }
    }

    private func buildContent() {
        contentStack.addArrangedSubview(makeHeader())
        if !data.routeCoordinates.isEmpty {
            contentStack.addArrangedSubview(makeRouteCard())
        }
        contentStack.addArrangedSubview(makeHeroCard())
        contentStack.addArrangedSubview(makeInfoSection())
        if !data.splits.isEmpty {
            contentStack.addArrangedSubview(makeSplitsSection())
        }
        contentStack.addArrangedSubview(makeActionSection())
    }

    private func makeHeader() -> UIView {
        let container = UIView()

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        closeButton.tintColor = AppColor.UI.textPrimary
        closeButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        container.addSubview(closeButton)

        let titleLabel = UILabel()
        titleLabel.numberOfLines = 2
        titleLabel.text = "WORKOUT\nSUMMARY"
        titleLabel.font = .systemFont(ofSize: 28, weight: .black)
        titleLabel.textColor = AppColor.UI.textPrimary
        container.addSubview(titleLabel)

        closeButton.snp.makeConstraints { make in
            make.leading.top.equalToSuperview()
            make.width.height.equalTo(32)
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.leading.equalTo(closeButton.snp.trailing).offset(8)
            make.trailing.bottom.equalToSuperview()
        }

        return container
    }

    private func makeRouteCard() -> UIView {
        let card = makeCardView(cornerRadius: 28)
        let routeView = WorkoutRoutePreviewView(
            coordinates: data.routeCoordinates.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
            },
            accentColor: accentColor
        )
        card.addSubview(routeView)
        routeView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(14)
            make.height.equalTo(180)
        }

        let chip = PaddingLabel()
        chip.text = " ROUTE "
        chip.font = .systemFont(ofSize: 12, weight: .black)
        chip.textColor = accentColor
        chip.backgroundColor = AppColor.UI.backgroundGrouped.withAlphaComponent(0.92)
        chip.layer.cornerRadius = 10
        chip.layer.masksToBounds = true
        routeView.addSubview(chip)
        chip.snp.makeConstraints { make in
            make.leading.bottom.equalToSuperview().inset(12)
        }

        return card
    }

    private func makeHeroCard() -> UIView {
        let card = makeCardView(cornerRadius: 30)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        card.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(18)
        }

        let distanceTitle = makeSectionLabel("DISTANCE")
        let distanceValue = makeHeroMetric(
            value: String(format: "%.2f", data.totalDistance / 1000),
            unit: "KM",
            color: accentColor
        )
        let timeTitle = makeSectionLabel("TOTAL TIME")
        let timeValue = makeHeroMetric(
            value: formatDuration(data.totalDuration),
            unit: "MIN",
            color: AppColor.UI.textPrimary
        )

        stack.addArrangedSubview(distanceTitle)
        stack.addArrangedSubview(distanceValue)
        stack.addArrangedSubview(timeTitle)
        stack.addArrangedSubview(timeValue)
        return card
    }

    private func makeInfoSection() -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 12

        section.addArrangedSubview(
            makeMetricCard(
                title: "AVG PACE",
                value: formatPace(data.avgPace),
                unit: "/KM",
                tint: accentColor
            )
        )

        section.addArrangedSubview(
            makeMetricCard(
                title: "CALORIES",
                value: data.calories.map { String(format: "%.0f", $0) } ?? "--",
                unit: "KCAL",
                tint: AppColor.UI.workoutPause
            )
        )

        section.addArrangedSubview(
            makeMetricCard(
                title: "SESSION",
                value: data.isIndoor ? "INDOOR" : "OUTDOOR",
                unit: data.alreadySaved ? "SAVED" : "UNSAVED",
                tint: AppColor.UI.success
            )
        )

        return section
    }

    private func makeMetricCard(title: String, value: String, unit: String, tint: UIColor) -> UIView {
        let card = makeCardView(cornerRadius: 24)
        let titleLabel = makeSectionLabel(title)

        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .heavy)
        valueLabel.textColor = AppColor.UI.textPrimary
        valueLabel.text = value

        let unitLabel = UILabel()
        unitLabel.font = .systemFont(ofSize: 12, weight: .bold)
        unitLabel.textColor = tint
        unitLabel.text = unit

        let valueStack = UIStackView(arrangedSubviews: [valueLabel, unitLabel])
        valueStack.axis = .horizontal
        valueStack.alignment = .lastBaseline
        valueStack.spacing = 4

        let dot = UIView()
        dot.backgroundColor = tint
        dot.layer.cornerRadius = 6

        let row = UIStackView(arrangedSubviews: [titleLabel, UIView(), dot])
        row.axis = .horizontal
        row.alignment = .center

        card.addSubview(row)
        card.addSubview(valueStack)
        row.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
        }
        dot.snp.makeConstraints { make in
            make.width.height.equalTo(12)
        }
        valueStack.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(16)
            make.top.equalTo(row.snp.bottom).offset(10)
        }
        return card
    }

    private func makeSplitsSection() -> UIView {
        let section = UIStackView()
        section.axis = .vertical
        section.spacing = 10

        let title = makeSectionLabel("LAPS")
        title.font = .systemFont(ofSize: 18, weight: .black)
        section.addArrangedSubview(title)

        let paces = data.splits.map(\.pace)
        let fastest = paces.min()

        for split in data.splits {
            let isFastest = split.pace == fastest
            section.addArrangedSubview(makeSplitCard(split: split, highlighted: isFastest))
        }

        return section
    }

    private func makeSplitCard(split: WorkoutResultDataModel.SplitData, highlighted: Bool) -> UIView {
        let card = makeCardView(cornerRadius: 22)
        if highlighted {
            card.layer.borderColor = accentColor.cgColor
            card.layer.borderWidth = 1.5
        }

        let kmLabel = UILabel()
        kmLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .bold)
        kmLabel.textColor = highlighted ? accentColor : AppColor.UI.textPrimary
        kmLabel.text = split.distance < 1000
            ? String(format: "%.1f", split.distance / 1000)
            : "\(split.km)"

        let paceLabel = UILabel()
        paceLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .heavy)
        paceLabel.textColor = highlighted ? accentColor : AppColor.UI.textPrimary
        paceLabel.text = formatPace(split.pace)

        let unitLabel = UILabel()
        unitLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        unitLabel.textColor = AppColor.UI.textSecondary
        unitLabel.text = split.distance < 1000 ? "km" : "/KM"

        let leftStack = UIStackView(arrangedSubviews: [kmLabel, UILabel()])
        leftStack.axis = .horizontal

        let rightStack = UIStackView(arrangedSubviews: [paceLabel, unitLabel])
        rightStack.axis = .horizontal
        rightStack.alignment = .lastBaseline
        rightStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [kmLabel, UIView(), rightStack])
        row.axis = .horizontal
        row.alignment = .center
        card.addSubview(row)
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
        }
        card.snp.makeConstraints { $0.height.equalTo(64) }
        return card
    }

    private func makeActionSection() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12

        let doneButton = UIButton(type: .system)
        doneButton.setTitle("FINISH REVIEW", for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .black)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.backgroundColor = accentColor
        doneButton.layer.cornerRadius = 24
        doneButton.layer.shadowColor = accentColor.cgColor
        doneButton.layer.shadowOpacity = 0.18
        doneButton.layer.shadowRadius = 16
        doneButton.layer.shadowOffset = CGSize(width: 0, height: 10)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.snp.makeConstraints { $0.height.equalTo(56) }
        stack.addArrangedSubview(doneButton)

        if data.workout != nil {
            let discardButton = UIButton(type: .system)
            discardButton.setTitle("운동 삭제", for: .normal)
            discardButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
            discardButton.setTitleColor(AppColor.UI.workoutStop, for: .normal)
            discardButton.backgroundColor = AppColor.UI.cardBackground
            discardButton.layer.cornerRadius = 22
            discardButton.layer.borderWidth = 1
            discardButton.layer.borderColor = AppColor.UI.border.cgColor
            discardButton.addTarget(self, action: #selector(discardTapped), for: .touchUpInside)
            discardButton.snp.makeConstraints { $0.height.equalTo(52) }
            stack.addArrangedSubview(discardButton)
        }

        return stack
    }

    private func makeHeroMetric(value: String, unit: String, color: UIColor) -> UIView {
        let valueLabel = UILabel()
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 52, weight: .black)
        valueLabel.textColor = color
        valueLabel.text = value
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.7

        let unitLabel = UILabel()
        unitLabel.font = .systemFont(ofSize: 18, weight: .black)
        unitLabel.textColor = AppColor.UI.textSecondary
        unitLabel.text = unit

        let stack = UIStackView(arrangedSubviews: [valueLabel, unitLabel])
        stack.axis = .horizontal
        stack.alignment = .lastBaseline
        stack.spacing = 6
        return stack
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .black)
        label.textColor = AppColor.UI.textSecondary
        label.text = text
        return label
    }

    private func makeCardView(cornerRadius: CGFloat) -> UIView {
        let view = UIView()
        view.backgroundColor = AppColor.UI.cardBackground
        view.layer.cornerRadius = cornerRadius
        view.layer.borderWidth = 1
        view.layer.borderColor = AppColor.UI.border.withAlphaComponent(0.7).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.06
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
        return view
    }

    @objc private func doneTapped() {
        dismiss(animated: true) { [weak self] in self?.onDismiss?() }
    }

    @objc private func discardTapped() {
        guard let workout = data.workout else { return }
        let alert = UIAlertController(title: "운동 삭제", message: "이 운동 데이터를 삭제하시겠습니까?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.view.isUserInteractionEnabled = false
            HealthKitStore.shared.deleteWorkout(workout) { [weak self] success, error in
                guard let self else { return }
                self.view.isUserInteractionEnabled = true
                if success {
                    self.dismiss(animated: true) { self.onDismiss?() }
                } else {
                    self.showAlert(title: "삭제 실패", message: error?.localizedDescription ?? "운동을 삭제하지 못했습니다.")
                }
            }
        })
        present(alert, animated: true)
    }

    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default) { _ in completion?() })
        present(alert, animated: true)
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
}

