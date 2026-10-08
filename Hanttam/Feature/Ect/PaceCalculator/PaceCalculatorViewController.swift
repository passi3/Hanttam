import UIKit
import SnapKit

final class PaceCalculatorViewController: HTViewController {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let targetControl = UISegmentedControl(items: PaceCalculator.Target.allCases.map(\.title))
    private let distanceField = UITextField()
    private let paceButton = UIButton(type: .system)
    private let timeButton = UIButton(type: .system)
    private var input = PaceCalculator.Input()
    private let resultTitleLabel = UILabel()
    private let resultLabel = UILabel()
    private let errorLabel = UILabel()
    private var inputSections: [PaceCalculator.Target: UIView] = [:]

    private var target: PaceCalculator.Target {
        PaceCalculator.Target(rawValue: targetControl.selectedSegmentIndex) ?? .pace
    }

    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        stack.axis = .vertical
        stack.spacing = 24
        stack.addArrangedSubview(targetControl)

        addDurationSection(.pace, title: "페이스 /km", button: paceButton)
        addInputSection(.distance, title: "거리", fields: [
            (distanceField, "km", "거리 킬로미터")
        ])
        addDurationSection(.time, title: "시간", button: timeButton)

        let separator = UIView()
        separator.backgroundColor = AppColor.UI.separator
        separator.snp.makeConstraints { $0.height.equalTo(1) }
        stack.addArrangedSubview(separator)
        let resultStack = UIStackView(arrangedSubviews: [resultTitleLabel, resultLabel, errorLabel])
        resultStack.axis = .vertical
        resultStack.spacing = 12
        stack.addArrangedSubview(resultStack)
    }

    override func configLayout() {
        scrollView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
        stack.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide).inset(20)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-40)
        }
        targetControl.snp.makeConstraints { $0.height.greaterThanOrEqualTo(36) }
    }

    override func configView() {
        title = "페이스 계산기"
        view.backgroundColor = AppColor.UI.backgroundGrouped
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        targetControl.selectedSegmentIndex = 0
        targetControl.accessibilityLabel = "계산할 항목"
        targetControl.accessibilityIdentifier = "calculator.target"
        targetControl.addTarget(self, action: #selector(targetChanged), for: .valueChanged)

        resultTitleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        resultTitleLabel.textColor = AppColor.UI.textSecondary
        resultTitleLabel.adjustsFontForContentSizeCategory = true
        resultLabel.font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: AppFont.UI.metricHero)
        resultLabel.adjustsFontForContentSizeCategory = true
        resultLabel.textColor = AppColor.UI.primary
        resultLabel.numberOfLines = 0
        resultLabel.accessibilityIdentifier = "calculator.result"
        errorLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = AppColor.UI.red
        errorLabel.numberOfLines = 0

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "arrow.counterclockwise"),
            style: .plain, target: self, action: #selector(reset)
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = "입력값 초기화"
        updateDurationButtons()
        updateTarget()
    }

    private func addDurationSection(_ target: PaceCalculator.Target, title: String, button: UIButton) {
        let label = UILabel()
        label.text = title
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = AppColor.UI.textPrimary

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "chevron.up.chevron.down")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 12
        configuration.contentInsets = .init(top: 16, leading: 16, bottom: 16, trailing: 16)
        configuration.background.backgroundColor = AppColor.UI.cardBackground
        configuration.background.cornerRadius = 8
        configuration.baseForegroundColor = AppColor.UI.textPrimary
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: AppFont.UI.metricBody)
            return attributes
        }
        button.configuration = configuration
        button.titleLabel?.numberOfLines = 0
        button.accessibilityLabel = title
        button.accessibilityIdentifier = "calculator.\(target == .pace ? "pace" : "time")"
        button.addAction(UIAction { [weak self] _ in
            self?.presentDurationPicker(for: target)
        }, for: .touchUpInside)
        button.snp.makeConstraints { $0.height.greaterThanOrEqualTo(52) }

        let section = UIStackView(arrangedSubviews: [label, button])
        section.axis = .vertical
        section.spacing = 12
        inputSections[target] = section
        stack.addArrangedSubview(section)
    }

    private func presentDurationPicker(for target: PaceCalculator.Target) {
        view.endEditing(true)
        let isPace = target == .pace
        let values = isPace
            ? [Int(input.paceMinutes) ?? 0, Int(input.paceSeconds) ?? 0]
            : [Int(input.hours) ?? 0, Int(input.minutes) ?? 0, Int(input.seconds) ?? 0]
        let picker = PaceDurationPickerViewController(mode: isPace ? .pace : .time, values: values) { [weak self] values in
            guard let self else { return }
            if isPace {
                self.input.paceMinutes = String(values[0])
                self.input.paceSeconds = String(values[1])
            } else {
                self.input.hours = String(values[0])
                self.input.minutes = String(values[1])
                self.input.seconds = String(values[2])
            }
            self.updateDurationButtons()
            self.inputChanged()
        }
        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersEdgeAttachedInCompactHeight = true
        }
        present(navigation, animated: true)
    }

    private func updateDurationButtons() {
        let pace = input.paceMinutes.isEmpty ? "분 · 초 선택" : "\(input.paceMinutes)분 \(input.paceSeconds)초"
        let time = input.hours.isEmpty ? "시 · 분 · 초 선택" : "\(input.hours)시간 \(input.minutes)분 \(input.seconds)초"
        paceButton.configuration?.title = pace
        timeButton.configuration?.title = time
        paceButton.accessibilityValue = pace
        timeButton.accessibilityValue = time
    }

    private func addInputSection(
        _ target: PaceCalculator.Target,
        title: String,
        fields: [(UITextField, String, String)]
    ) {
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = AppColor.UI.textPrimary
        let row = UIStackView()
        row.spacing = 12
        row.distribution = .fillEqually
        for (field, unit, accessibilityLabel) in fields {
            field.placeholder = "0"
            field.keyboardType = target == .distance ? .decimalPad : .numberPad
            field.borderStyle = .none
            field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: AppFont.UI.metricBody)
            field.adjustsFontForContentSizeCategory = true
            field.textAlignment = .center
            field.textColor = AppColor.UI.textPrimary
            field.backgroundColor = AppColor.UI.cardBackground
            field.layer.cornerRadius = 8
            field.accessibilityLabel = accessibilityLabel
            field.accessibilityIdentifier = "calculator.\(accessibilityLabel)"
            field.addTarget(self, action: #selector(inputChanged), for: .editingChanged)
            field.addTarget(self, action: #selector(editingBegan(_:)), for: .editingDidBegin)
            field.snp.makeConstraints { $0.height.greaterThanOrEqualTo(52) }

            let toolbar = UIToolbar()
            toolbar.items = [
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(title: "완료", style: .done, target: self, action: #selector(dismissKeyboard))
            ]
            toolbar.sizeToFit()
            field.inputAccessoryView = toolbar

            let unitLabel = UILabel()
            unitLabel.text = unit
            unitLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
            unitLabel.adjustsFontForContentSizeCategory = true
            unitLabel.textColor = AppColor.UI.textSecondary
            unitLabel.textAlignment = .center
            let column = UIStackView(arrangedSubviews: [field, unitLabel])
            column.axis = .vertical
            column.spacing = 6
            row.addArrangedSubview(column)
        }
        let section = UIStackView(arrangedSubviews: [titleLabel, row])
        section.axis = .vertical
        section.spacing = 12
        inputSections[target] = section
        stack.addArrangedSubview(section)
    }

    @objc private func targetChanged() {
        view.endEditing(true)
        updateTarget()
    }

    private func updateTarget() {
        for (item, section) in inputSections {
            section.isHidden = item == target
        }
        resultTitleLabel.text = "\(target.title) 계산 결과"
        inputChanged()
    }

    @objc private func inputChanged() {
        input.distance = distanceField.text ?? ""
        do {
            let result = try PaceCalculator.calculate(target, input: input)
            resultLabel.text = PaceCalculator.formatted(result, for: target)
            errorLabel.text = nil
        } catch {
            resultLabel.text = "--"
            errorLabel.text = (error as? PaceCalculator.ValidationError)?.errorDescription
        }
        errorLabel.isHidden = errorLabel.text == nil
    }

    @objc private func reset() {
        input = PaceCalculator.Input()
        distanceField.text = nil
        updateDurationButtons()
        inputChanged()
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func editingBegan(_ field: UITextField) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak field] in
            guard let self, let field, field.isFirstResponder else { return }
            let rect = field.convert(field.bounds, to: self.scrollView).insetBy(dx: 0, dy: -16)
            self.scrollView.scrollRectToVisible(rect, animated: true)
        }
    }
}
