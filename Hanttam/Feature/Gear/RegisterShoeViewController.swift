//
//  RegisterShoeViewController.swift
//  Hanttam
//
//  Created by Codex on 4/8/26.
//

import UIKit
import RxCocoa
import RxSwift
import SnapKit

final class RegisterShoeViewController: HTViewController {
    private let viewModel: RegisterShoeViewModel
    private let onRegistered: ((RegisteredShoe) -> Void)?
    private let saveTapSubject = PublishSubject<Void>()
    private let disposeBag = DisposeBag()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let shoeImageView = UIImageView()
    private let brandLabel = UILabel()
    private let modelLabel = UILabel()
    private let metaLabel = UILabel()
    private let distanceTitleLabel = UILabel()
    private let targetField = UITextField()
    private let helperLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private var imageTask: URLSessionDataTask?

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
            distanceTitleLabel,
            targetField,
            helperLabel,
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
        distanceTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(metaLabel.snp.bottom).offset(32)
            make.leading.trailing.equalTo(brandLabel)
        }
        targetField.snp.makeConstraints { make in
            make.top.equalTo(distanceTitleLabel.snp.bottom).offset(12)
            make.leading.trailing.equalTo(brandLabel)
            make.height.equalTo(52)
        }
        helperLabel.snp.makeConstraints { make in
            make.top.equalTo(targetField.snp.bottom).offset(10)
            make.leading.trailing.equalTo(brandLabel)
        }
        saveButton.snp.makeConstraints { make in
            make.top.equalTo(helperLabel.snp.bottom).offset(28)
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

        targetField.borderStyle = .none
        targetField.layer.cornerRadius = 14
        targetField.layer.borderWidth = 1
        targetField.layer.borderColor = AppColor.UI.border.cgColor
        targetField.backgroundColor = AppColor.UI.cardBackground
        targetField.font = AppFont.UI.titleMD
        targetField.keyboardType = .decimalPad
        targetField.placeholder = "예: 600"
        targetField.setLeftPadding(16)
        targetField.setRightPadding(16)

        helperLabel.font = AppFont.UI.bodySM
        helperLabel.textColor = AppColor.UI.textSecondary
        helperLabel.text = "km 단위로 입력하면 내부에서는 meter로 저장됩니다."

        saveButton.setTitle("운동화 등록", for: .normal)
        saveButton.backgroundColor = AppColor.UI.primary
        saveButton.setTitleColor(.white, for: .normal)
        saveButton.titleLabel?.font = AppFont.UI.buttonMD
        saveButton.layer.cornerRadius = 16
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
    }

    private func bind() {
        let output = viewModel.transform(
            input: .init(
                targetDistanceText: targetField.rx.text.orEmpty.asObservable(),
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

        output.isSaving
            .drive(onNext: { [weak self] saving in
                self?.saveButton.isEnabled = !saving
                self?.saveButton.alpha = saving ? 0.6 : 1.0
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

    private func showAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
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
