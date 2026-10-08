import UIKit
import SnapKit

final class PaceDurationPickerViewController: HTViewController, UIPickerViewDataSource, UIPickerViewDelegate {
    enum Mode {
        case pace, time

        var units: [String] {
            self == .pace ? ["분", "초"] : ["시간", "분", "초"]
        }

        var title: String { self == .pace ? "페이스 /km" : "시간" }
    }

    private let mode: Mode
    private var values: [Int]
    private let onConfirm: ([Int]) -> Void
    private let picker = UIPickerView()

    init(mode: Mode, values: [Int], onConfirm: @escaping ([Int]) -> Void) {
        self.mode = mode
        self.values = mode.units.indices.map { index in
            let value = values.indices.contains(index) ? values[index] : 0
            return min(max(value, 0), index == 0 ? 99 : 59)
        }
        self.onConfirm = onConfirm
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func configHierarchy() {
        view.addSubview(picker)
    }

    override func configLayout() {
        picker.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.centerY.equalTo(view.safeAreaLayoutGuide)
            make.top.greaterThanOrEqualTo(view.safeAreaLayoutGuide)
            make.bottom.lessThanOrEqualTo(view.safeAreaLayoutGuide)
        }
    }

    override func configView() {
        title = mode.title
        view.backgroundColor = AppColor.UI.backgroundGrouped
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "취소", style: .plain, target: self, action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "완료", style: .done, target: self, action: #selector(confirm)
        )
        picker.dataSource = self
        picker.delegate = self
        picker.accessibilityIdentifier = "calculator.durationPicker"
        for (component, value) in values.enumerated() {
            picker.selectRow(value, inComponent: component, animated: false)
        }
        updateConfirmation()
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int { mode.units.count }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? 100 : 60
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        "\(row)\(mode.units[component])"
    }

    func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
        mode.units[component]
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        values[component] = row
        updateConfirmation()
    }

    private func updateConfirmation() {
        navigationItem.rightBarButtonItem?.isEnabled = values.contains { $0 > 0 }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func confirm() {
        guard values.contains(where: { $0 > 0 }) else { return }
        onConfirm(values)
        dismiss(animated: true)
    }
}
