//
//  RegisterShoeViewController.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import UIKit
import RxCocoa
import RxSwift
import SnapKit

final class RegisterShoeViewController: HTViewController {
    private enum DistanceOption {
        static let targetDistances: [Double] = stride(from: 100_000.0, through: 1_500_000.0, by: 100_000.0).map { $0 }
        static let previousDistanceAlertMessage = "현재 거리는 0km 이상, 목표 거리 이하로 입력해주세요."
        static let targetDistanceRequiredMessage = "먼저 목표 거리를 선택해주세요."
    }

    private let viewModel: RegisterShoeViewModel
    private let onRegistered: ((RegisteredShoe) -> Void)?
    private let saveTapSubject = PublishSubject<Void>()
    private let targetDistanceSubject = BehaviorSubject<Double?>(value: nil)
    private let disposeBag = DisposeBag()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let shoeImageView = UIImageView()
    private let infoStack = UIStackView()
    private let brandLabel = UILabel()
    private let modelLabel = UILabel()
    private let metaLabel = UILabel()
    private let formStack = UIStackView()
    private let nicknameTitleLabel = UILabel()
    private let nicknameField = UITextField()
    private let distanceTitleLabel = UILabel()
    private let targetDistanceField = UITextField()
    private let previousDistanceTitleLabel = UILabel()
    private let previousDistanceField = UITextField()
    private let saveButton = UIButton(type: .system)
    private let targetDistancePicker = UIPickerView()
    private let targetDistanceToolbar = UIToolbar()
    private let previousDistanceToolbar = UIToolbar()
    private var imageTask: URLSessionDataTask?
    private var selectedTargetDistanceMeters: Double?
    private var canRegister = false

    init(mode: RegisterShoeViewModel.Mode, onRegistered: ((RegisteredShoe) -> Void)? = nil) {
        self.viewModel = RegisterShoeViewModel(mode: mode)
        self.onRegistered = onRegistered
        super.init(nibName: nil, bundle: nil)
    }

    convenience init(item: ShoeCatalogItem, onRegistered: ((RegisteredShoe) -> Void)? = nil) {
        self.init(mode: .catalog(item), onRegistered: onRegistered)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
    }

    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(shoeImageView)
        contentView.addSubview(formStack)

        [brandLabel, modelLabel, metaLabel].forEach { infoStack.addArrangedSubview($0) }

        [
            infoStack,
            nicknameTitleLabel,
            nicknameField,
            distanceTitleLabel,
            targetDistanceField,
            previousDistanceTitleLabel,
            previousDistanceField,
            saveButton
        ].forEach { formStack.addArrangedSubview($0) }
    }

    override func configLayout() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
        }
        shoeImageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(24)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(180)
        }
        formStack.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(32)
        }
        nicknameField.snp.makeConstraints { make in
            make.height.equalTo(52)
        }
        targetDistanceField.snp.makeConstraints { make in
            make.height.equalTo(52)
        }
        previousDistanceField.snp.makeConstraints { make in
            make.height.equalTo(52)
        }
        saveButton.snp.makeConstraints { make in
            make.height.equalTo(54)
        }
    }

    override func configView() {
        title = "운동화 등록"
        view.backgroundColor = AppColor.UI.backgroundGrouped

        shoeImageView.contentMode = .scaleAspectFit
        shoeImageView.layer.cornerRadius = 22
        shoeImageView.clipsToBounds = true
        shoeImageView.backgroundColor = AppColor.UI.backgroundSecondary
        shoeImageView.tintColor = AppColor.UI.textSecondary
        shoeImageView.image = UIImage(systemName: "shoe")

        formStack.axis = .vertical
        formStack.alignment = .fill
        formStack.distribution = .fill
        formStack.spacing = 12
        formStack.setCustomSpacing(24, after: infoStack)
        formStack.setCustomSpacing(24, after: nicknameField)
        formStack.setCustomSpacing(24, after: targetDistanceField)
        formStack.setCustomSpacing(28, after: previousDistanceField)

        infoStack.axis = .vertical
        infoStack.alignment = .fill
        infoStack.distribution = .fill
        infoStack.spacing = 6

        brandLabel.font = AppFont.UI.labelLG
        brandLabel.textColor = AppColor.UI.textSecondary
        brandLabel.textAlignment = .center

        modelLabel.font = AppFont.UI.headlineSM
        modelLabel.textColor = AppColor.UI.textPrimary
        modelLabel.textAlignment = .center
        modelLabel.numberOfLines = 2

        metaLabel.font = AppFont.UI.bodyMD
        metaLabel.textColor = AppColor.UI.textSecondary
        metaLabel.numberOfLines = 0
        metaLabel.textAlignment = .center

        distanceTitleLabel.font = AppFont.UI.titleMD
        distanceTitleLabel.textColor = AppColor.UI.textPrimary
        distanceTitleLabel.text = "목표 거리"

        nicknameTitleLabel.font = AppFont.UI.titleMD
        nicknameTitleLabel.textColor = AppColor.UI.textPrimary
        nicknameTitleLabel.text = "별칭"

        previousDistanceTitleLabel.font = AppFont.UI.titleMD
        previousDistanceTitleLabel.textColor = AppColor.UI.textPrimary
        previousDistanceTitleLabel.text = "현재 거리(km)"

        nicknameField.borderStyle = .none
        nicknameField.layer.cornerRadius = 14
        nicknameField.layer.borderWidth = 1
        nicknameField.layer.borderColor = AppColor.UI.border.cgColor
        nicknameField.backgroundColor = AppColor.UI.cardBackground
        nicknameField.font = AppFont.UI.titleMD
        nicknameField.attributedPlaceholder = NSAttributedString(
            string: "별칭을 입력하세요",
            attributes: [.foregroundColor: AppColor.UI.textTertiary]
        )
        nicknameField.setLeftPadding(16)
        nicknameField.setRightPadding(16)
        nicknameField.returnKeyType = .done
        nicknameField.delegate = self

        targetDistanceField.borderStyle = .none
        targetDistanceField.layer.cornerRadius = 14
        targetDistanceField.layer.borderWidth = 1
        targetDistanceField.layer.borderColor = AppColor.UI.border.cgColor
        targetDistanceField.backgroundColor = AppColor.UI.cardBackground
        targetDistanceField.font = AppFont.UI.titleMD
        targetDistanceField.tintColor = .clear
        targetDistanceField.attributedPlaceholder = NSAttributedString(
            string: "목표 거리를 선택하세요",
            attributes: [.foregroundColor: AppColor.UI.textTertiary]
        )
        targetDistanceField.setLeftPadding(16)
        targetDistanceField.setRightPadding(40)
        targetDistanceField.inputView = targetDistancePicker
        targetDistanceField.inputAccessoryView = targetDistanceToolbar
        targetDistanceField.delegate = self

        targetDistancePicker.dataSource = self
        targetDistancePicker.delegate = self

        previousDistanceField.borderStyle = .none
        previousDistanceField.layer.cornerRadius = 14
        previousDistanceField.layer.borderWidth = 1
        previousDistanceField.layer.borderColor = AppColor.UI.border.cgColor
        previousDistanceField.backgroundColor = AppColor.UI.cardBackground
        previousDistanceField.font = AppFont.UI.titleMD
        previousDistanceField.keyboardType = .decimalPad
        previousDistanceField.returnKeyType = .done
        previousDistanceField.attributedPlaceholder = NSAttributedString(
            string: "현재 거리를 입력하세요",
            attributes: [.foregroundColor: AppColor.UI.textTertiary]
        )
        previousDistanceField.setLeftPadding(16)
        previousDistanceField.setRightPadding(16)
        previousDistanceField.inputAccessoryView = previousDistanceToolbar
        previousDistanceField.delegate = self

        saveButton.setTitle("운동화 등록", for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.titleLabel?.font = AppFont.UI.buttonMD
        saveButton.layer.cornerRadius = 16
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        configureToolbar(targetDistanceToolbar, action: #selector(confirmTargetDistanceSelection))
        configureToolbar(previousDistanceToolbar, action: #selector(confirmPreviousDistanceEntry))
        applySaveButtonStyle(isEnabled: false)
    }

    private func bind() {
        let output = viewModel.transform(
            input: .init(
                nicknameText: nicknameField.rx.text.orEmpty.asObservable(),
                selectedTargetDistance: targetDistanceSubject.asObservable(),
                previousDistanceText: previousDistanceField.rx.text.orEmpty.asObservable(),
                saveTap: saveTapSubject.asObservable()
            )
        )

        output.item
            .drive(onNext: { [weak self] item in
                guard let self else { return }
                if let item {
                    self.brandLabel.text = item.brandName.uppercased()
                    self.modelLabel.text = item.modelName
                    self.metaLabel.text = [item.sku, item.colors.joined(separator: ", ")]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                    self.imageTask = RemoteImageLoader.shared.loadImage(from: item.imageURL) { [weak self] image in
                        self?.shoeImageView.image = image ?? UIImage(systemName: "shoe")
                        self?.shoeImageView.tintColor = AppColor.UI.textSecondary
                    }
                } else {
                    self.brandLabel.text = nil
                    self.modelLabel.text = nil
                    self.metaLabel.text = nil
                    self.shoeImageView.image = UIImage(systemName: "shoe")
                    self.shoeImageView.tintColor = AppColor.UI.textSecondary
                }
            })
            .disposed(by: disposeBag)

        output.isManual
            .drive(onNext: { [weak self] isManual in
                guard let self else { return }
                // In manual mode the catalog info group collapses and nickname becomes required.
                self.infoStack.isHidden = isManual
                if isManual {
                    self.nicknameField.attributedPlaceholder = NSAttributedString(
                        string: "운동화 이름 또는 별칭을 입력하세요",
                        attributes: [.foregroundColor: AppColor.UI.textTertiary]
                    )
                    self.formStack.setCustomSpacing(0, after: self.infoStack)
                }
            })
            .disposed(by: disposeBag)

        output.targetDistanceText
            .drive(onNext: { [weak self] text in
                self?.updateTargetDistanceFieldText(text)
            })
            .disposed(by: disposeBag)

        output.isRegisterEnabled
            .drive(onNext: { [weak self] isEnabled in
                self?.canRegister = isEnabled
                self?.updateSaveButtonState(isSaving: false)
            })
            .disposed(by: disposeBag)

        output.isSaving
            .drive(onNext: { [weak self] saving in
                self?.updateSaveButtonState(isSaving: saving)
            })
            .disposed(by: disposeBag)

        output.errorMessage
            .emit(onNext: { [weak self] message in
                self?.showAlert(message: message)
            })
            .disposed(by: disposeBag)

        output.registeredShoe
            .emit(onNext: { [weak self] shoe in
                guard let self else { return }
                self.onRegistered?(shoe)
                if let navigationController = self.navigationController, navigationController.presentingViewController != nil {
                    navigationController.dismiss(animated: true)
                } else {
                    self.navigationController?.popToRootViewController(animated: true)
                }
            })
            .disposed(by: disposeBag)
    }

    @objc private func saveTapped() {
        saveTapSubject.onNext(())
    }

    @objc private func confirmTargetDistanceSelection() {
        if selectedTargetDistanceMeters == nil,
           let firstDistance = DistanceOption.targetDistances.first {
            selectTargetDistance(firstDistance)
        }
        targetDistanceField.resignFirstResponder()
    }

    @objc private func confirmPreviousDistanceEntry() {
        _ = validatePreviousDistanceAndDismissKeyboardIfNeeded()
    }

    private func configureToolbar(_ toolbar: UIToolbar, action: Selector) {
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "완료", style: .done, target: self, action: action)
        ]
    }

    @discardableResult
    private func validatePreviousDistanceAndDismissKeyboardIfNeeded() -> Bool {
        let text = previousDistanceField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty {
            previousDistanceField.resignFirstResponder()
            return true
        }

        guard let selectedTargetDistanceMeters else {
            showAlert(message: DistanceOption.targetDistanceRequiredMessage)
            return false
        }

        let isValid = viewModel.validatePreviousDistance(text, targetDistanceMeters: selectedTargetDistanceMeters)
        guard isValid else {
            showAlert(message: DistanceOption.previousDistanceAlertMessage)
            return false
        }

        previousDistanceField.resignFirstResponder()
        return true
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }

    private func selectTargetDistance(_ distance: Double) {
        selectedTargetDistanceMeters = distance
        targetDistanceSubject.onNext(distance)
    }

    private func updateTargetDistanceFieldText(_ text: String?) {
        if let text, !text.isEmpty {
            targetDistanceField.text = text
            targetDistanceField.textColor = AppColor.UI.textPrimary
        } else {
            targetDistanceField.text = nil
            targetDistanceField.textColor = AppColor.UI.textTertiary
        }
    }

    private func applySaveButtonStyle(isEnabled: Bool) {
        let accentColor = RunningLevelManager.shared.accentUIColor
        saveButton.backgroundColor = isEnabled ? accentColor : accentColor.withAlphaComponent(0.35)
    }

    private func updateSaveButtonState(isSaving: Bool) {
        let isEnabled = canRegister && !isSaving
        saveButton.isEnabled = isEnabled
        saveButton.alpha = isEnabled ? 1.0 : 0.6
        applySaveButtonStyle(isEnabled: isEnabled)
    }
}

extension RegisterShoeViewController: UITextFieldDelegate {
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField === targetDistanceField {
            let distance = selectedTargetDistanceMeters ?? DistanceOption.targetDistances.first
            if let distance,
               let index = DistanceOption.targetDistances.firstIndex(of: distance) {
                targetDistancePicker.selectRow(index, inComponent: 0, animated: false)
            }
        }
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === nicknameField {
            textField.resignFirstResponder()
            return true
        }
        guard textField === previousDistanceField else { return true }
        return validatePreviousDistanceAndDismissKeyboardIfNeeded()
    }
}

extension RegisterShoeViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        DistanceOption.targetDistances.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        let distance = DistanceOption.targetDistances[row]
        return "\(Int(distance / 1000.0)) km"
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        selectTargetDistance(DistanceOption.targetDistances[row])
    }
}

private extension UITextField {
    func setLeftPadding(_ value: CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        leftView = paddingView
        leftViewMode = .always
    }

    func setRightPadding(_ value: CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        rightView = paddingView
        rightViewMode = .always
    }
}
