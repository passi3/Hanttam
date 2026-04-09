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
        static let previousDistanceAlertMessage = "이전 달린 거리는 0km 이상, 목표 거리 이하로 입력해주세요."
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
    private let brandLabel = UILabel()
    private let modelLabel = UILabel()
    private let metaLabel = UILabel()
    private let nicknameTitleLabel = UILabel()
    private let nicknameField = UITextField()
    private let distanceTitleLabel = UILabel()
    private let targetDistanceButton = UIButton(type: .system)
    private let previousDistanceTitleLabel = UILabel()
    private let previousDistanceField = UITextField()
    private let saveButton = UIButton(type: .system)
    private let previousDistanceToolbar = UIToolbar()
    private var imageTask: URLSessionDataTask?
    private var selectedTargetDistanceMeters: Double?
    private var canRegister = false

    init(item: ShoeCatalogItem, onRegistered: ((RegisteredShoe) -> Void)? = nil) {
        self.viewModel = RegisterShoeViewModel(item: item)
        self.onRegistered = onRegistered
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
    }

    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        [
            shoeImageView,
            brandLabel,
            modelLabel,
            metaLabel,
            nicknameTitleLabel,
            nicknameField,
            distanceTitleLabel,
            targetDistanceButton,
            previousDistanceTitleLabel,
            previousDistanceField,
            saveButton
        ].forEach { contentView.addSubview($0) }
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
        brandLabel.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        modelLabel.snp.makeConstraints { make in
            make.top.equalTo(brandLabel.snp.bottom).offset(6)
            make.leading.trailing.equalTo(brandLabel)
        }
        metaLabel.snp.makeConstraints { make in
            make.top.equalTo(modelLabel.snp.bottom).offset(10)
            make.leading.trailing.equalTo(brandLabel)
        }
        nicknameTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(metaLabel.snp.bottom).offset(32)
            make.leading.trailing.equalTo(brandLabel)
        }
        nicknameField.snp.makeConstraints { make in
            make.top.equalTo(nicknameTitleLabel.snp.bottom).offset(12)
            make.leading.trailing.equalTo(brandLabel)
            make.height.equalTo(52)
        }
        distanceTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(nicknameField.snp.bottom).offset(24)
            make.leading.trailing.equalTo(brandLabel)
        }
        targetDistanceButton.snp.makeConstraints { make in
            make.top.equalTo(distanceTitleLabel.snp.bottom).offset(12)
            make.leading.trailing.equalTo(brandLabel)
            make.height.equalTo(52)
        }
        previousDistanceTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(targetDistanceButton.snp.bottom).offset(24)
            make.leading.trailing.equalTo(brandLabel)
        }
        previousDistanceField.snp.makeConstraints { make in
            make.top.equalTo(previousDistanceTitleLabel.snp.bottom).offset(12)
            make.leading.trailing.equalTo(brandLabel)
            make.height.equalTo(52)
        }
        saveButton.snp.makeConstraints { make in
            make.top.equalTo(previousDistanceField.snp.bottom).offset(28)
            make.leading.trailing.equalTo(brandLabel)
            make.height.equalTo(54)
            make.bottom.equalToSuperview().inset(32)
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
        shoeImageView.image = UIImage(systemName: "shoeprints.fill")

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
        nicknameTitleLabel.text = "별명"

        previousDistanceTitleLabel.font = AppFont.UI.titleMD
        previousDistanceTitleLabel.textColor = AppColor.UI.textPrimary
        previousDistanceTitleLabel.text = "이전 달린 거리"

        nicknameField.borderStyle = .none
        nicknameField.layer.cornerRadius = 14
        nicknameField.layer.borderWidth = 1
        nicknameField.layer.borderColor = AppColor.UI.border.cgColor
        nicknameField.backgroundColor = AppColor.UI.cardBackground
        nicknameField.font = AppFont.UI.titleMD
        nicknameField.placeholder = "별명을 입력해주세요"
        nicknameField.setLeftPadding(16)
        nicknameField.setRightPadding(16)
        nicknameField.returnKeyType = .done
        nicknameField.delegate = self

        targetDistanceButton.layer.cornerRadius = 14
        targetDistanceButton.layer.borderWidth = 1
        targetDistanceButton.layer.borderColor = AppColor.UI.border.cgColor
        targetDistanceButton.backgroundColor = AppColor.UI.cardBackground
        targetDistanceButton.contentHorizontalAlignment = .left
        targetDistanceButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        targetDistanceButton.setTitle("목표 거리를 선택하세요", for: .normal)
        targetDistanceButton.setTitleColor(AppColor.UI.textTertiary, for: .normal)
        targetDistanceButton.titleLabel?.font = AppFont.UI.titleMD
        targetDistanceButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        targetDistanceButton.tintColor = AppColor.UI.textSecondary
        targetDistanceButton.semanticContentAttribute = .forceRightToLeft
        targetDistanceButton.showsMenuAsPrimaryAction = true
        targetDistanceButton.changesSelectionAsPrimaryAction = false
        targetDistanceButton.menu = makeTargetDistanceMenu()

        previousDistanceField.borderStyle = .none
        previousDistanceField.layer.cornerRadius = 14
        previousDistanceField.layer.borderWidth = 1
        previousDistanceField.layer.borderColor = AppColor.UI.border.cgColor
        previousDistanceField.backgroundColor = AppColor.UI.cardBackground
        previousDistanceField.font = AppFont.UI.titleMD
        previousDistanceField.keyboardType = .decimalPad
        previousDistanceField.returnKeyType = .done
        previousDistanceField.placeholder = "예: 120.5"
        previousDistanceField.setLeftPadding(16)
        previousDistanceField.setRightPadding(16)
        previousDistanceField.inputAccessoryView = previousDistanceToolbar
        previousDistanceField.delegate = self

        saveButton.setTitle("운동화 등록", for: .normal)
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.titleLabel?.font = AppFont.UI.buttonMD
        saveButton.layer.cornerRadius = 16
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
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
                self?.brandLabel.text = item.brandName.uppercased()
                self?.modelLabel.text = item.modelName
                self?.metaLabel.text = [item.sku, item.colors.joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: "\n")
                self?.imageTask = RemoteImageLoader.shared.loadImage(from: item.imageURL) { image in
                    self?.shoeImageView.image = image ?? UIImage(systemName: "shoeprints.fill")
                    self?.shoeImageView.tintColor = AppColor.UI.textSecondary
                }
            })
            .disposed(by: disposeBag)

        output.targetDistanceText
            .drive(onNext: { [weak self] text in
                self?.updateTargetDistanceButtonTitle(text)
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

    private func makeTargetDistanceMenu() -> UIMenu {
        let actions = DistanceOption.targetDistances.map { distance in
            let kilometers = Int(distance / 1000.0)
            let isSelected = selectedTargetDistanceMeters == distance
            return UIAction(
                title: "\(kilometers) km",
                state: isSelected ? .on : .off
            ) { [weak self] _ in
                self?.selectedTargetDistanceMeters = distance
                self?.targetDistanceSubject.onNext(distance)
                self?.targetDistanceButton.menu = self?.makeTargetDistanceMenu()
            }
        }
        return UIMenu(title: "", children: actions)
    }

    private func updateTargetDistanceButtonTitle(_ text: String?) {
        if let text, !text.isEmpty {
            targetDistanceButton.setTitle(text, for: .normal)
            targetDistanceButton.setTitleColor(AppColor.UI.textPrimary, for: .normal)
        } else {
            targetDistanceButton.setTitle("목표 거리를 선택하세요", for: .normal)
            targetDistanceButton.setTitleColor(AppColor.UI.textTertiary, for: .normal)
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
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === nicknameField {
            textField.resignFirstResponder()
            return true
        }
        guard textField === previousDistanceField else { return true }
        return validatePreviousDistanceAndDismissKeyboardIfNeeded()
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
