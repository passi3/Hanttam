//
//  ShoeEditViewController.swift
//  Hanttam
//
//  Created by passi on 4/10/26.
//

import UIKit
import SnapKit

final class ShoeEditViewController: HTViewController {
    private enum DistanceOption {
        static let targetDistances: [Double] = stride(from: 100_000.0, through: 1_500_000.0, by: 100_000.0).map { $0 }
    }

    private let variantService: ShoeCatalogVariantServicing
    private let store: GearLocalStoring
    private let originalShoe: RegisteredShoe

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let previewView = ShoeEditPreviewView()
    private let formCardView = HTView()
    private let nicknameTitleLabel = UILabel()
    private let nicknameField = UITextField()
    private let targetDistanceTitleLabel = UILabel()
    private let targetDistanceField = UITextField()
    private lazy var saveBarButtonItem = UIBarButtonItem(
        title: "저장",
        style: .done,
        target: self,
        action: #selector(saveButtonTapped)
    )
    private let targetDistancePicker = UIPickerView()
    private let targetDistanceToolbar = UIToolbar()

    private var variants: [ShoeCatalogItem] = []
    private var selectedVariant: ShoeCatalogItem?
    private var selectedTargetDistanceMeters: Double?
    private var isApplyingState = false

    init(
        shoe: RegisteredShoe,
        variantService: ShoeCatalogVariantServicing = SupabaseShoeSearchService(),
        store: GearLocalStoring = GearLocalStore.shared
    ) {
        self.originalShoe = shoe
        self.variantService = variantService
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyCurrentState()
        fetchVariantsIfNeeded()
    }

    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)
        [nicknameTitleLabel, nicknameField, targetDistanceTitleLabel, targetDistanceField].forEach {
            formCardView.addSubview($0)
        }
        [previewView, formCardView].forEach { stackView.addArrangedSubview($0) }
    }

    override func configLayout() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
        }
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 20, left: 20, bottom: 32, right: 20))
        }

        nicknameTitleLabel.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(20)
        }
        nicknameField.snp.makeConstraints { make in
            make.top.equalTo(nicknameTitleLabel.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(52)
        }
        targetDistanceTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(nicknameField.snp.bottom).offset(18)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        targetDistanceField.snp.makeConstraints { make in
            make.top.equalTo(targetDistanceTitleLabel.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(20)
            make.height.equalTo(52)
        }
    }

    override func configView() {
        title = "운동화 수정"
        view.backgroundColor = AppColor.UI.backgroundGrouped
        navigationItem.rightBarButtonItem = saveBarButtonItem

        stackView.axis = .vertical
        stackView.spacing = 18

        formCardView.backgroundColor = AppColor.UI.cardBackground
        formCardView.layer.cornerRadius = 24
        formCardView.layer.borderWidth = 1
        formCardView.layer.borderColor = AppColor.UI.border.cgColor

        nicknameTitleLabel.font = AppFont.UI.titleMD
        nicknameTitleLabel.textColor = AppColor.UI.textPrimary
        nicknameTitleLabel.text = "별칭"

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

        targetDistanceTitleLabel.font = AppFont.UI.titleMD
        targetDistanceTitleLabel.textColor = AppColor.UI.textPrimary
        targetDistanceTitleLabel.text = "목표 거리"

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
        configureToolbar(targetDistanceToolbar)

        updateSaveButtonState()
    }

    private func fetchVariantsIfNeeded() {
        guard !originalShoe.brandName.isEmpty, !originalShoe.modelName.isEmpty else { return }
        variantService.fetchVariants(brandName: originalShoe.brandName, modelName: originalShoe.modelName) { [weak self] result in
            guard let self else { return }
            guard case .success(let items) = result else { return }
            variants = items
            previewView.configure(
                with: makePreviewShoe(),
                variants: items,
                onSelectVariant: { [weak self] item in
                    self?.selectedVariant = item
                    self?.refreshPreview()
                    self?.updateSaveButtonState()
                }
            )
        }
    }

    private func applyCurrentState() {
        isApplyingState = true
        nicknameField.text = originalShoe.nickname
        selectedTargetDistanceMeters = originalShoe.targetDistanceMeters
        updateTargetDistanceFieldText(for: originalShoe.targetDistanceMeters)
        previewView.configure(
            with: makePreviewShoe(),
            variants: variants,
            onSelectVariant: { [weak self] item in
                self?.selectedVariant = item
                self?.refreshPreview()
                self?.updateSaveButtonState()
            }
        )
        isApplyingState = false
        updateSaveButtonState()
    }

    private func refreshPreview() {
        previewView.configure(
            with: makePreviewShoe(),
            variants: variants,
            onSelectVariant: { [weak self] item in
                self?.selectedVariant = item
                self?.refreshPreview()
                self?.updateSaveButtonState()
            }
        )
    }

    private func makePreviewShoe() -> RegisteredShoe {
        let baseItem = selectedVariant ?? makeCatalogItem(from: originalShoe)
        return RegisteredShoe(
            id: originalShoe.id,
            catalogID: baseItem.id,
            nickname: normalizedNickname(),
            brandName: baseItem.brandName,
            modelName: baseItem.modelName,
            sku: baseItem.sku,
            colors: baseItem.colors,
            imageURL: baseItem.imageURL,
            createdAt: baseItem.createdAt,
            registeredAt: originalShoe.registeredAt,
            targetDistanceMeters: selectedTargetDistanceMeters ?? originalShoe.targetDistanceMeters,
            initialDistanceMeters: originalShoe.initialDistanceMeters
        )
    }

    private func makeEditedShoe() -> RegisteredShoe {
        makePreviewShoe()
    }

    private func makeCatalogItem(from shoe: RegisteredShoe) -> ShoeCatalogItem {
        ShoeCatalogItem(
            id: shoe.catalogID,
            modelName: shoe.modelName,
            sku: shoe.sku,
            colors: shoe.colors,
            imageURL: shoe.imageURL,
            createdAt: shoe.createdAt,
            brandName: shoe.brandName
        )
    }

    private func normalizedNickname() -> String? {
        let trimmed = nicknameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func hasChanges() -> Bool {
        makeEditedShoe() != originalShoe
    }

    private func updateTargetDistanceFieldText(for distance: Double?) {
        guard let distance else {
            targetDistanceField.text = nil
            targetDistanceField.textColor = AppColor.UI.textTertiary
            return
        }
        targetDistanceField.text = "\(Int(distance / 1000.0)) km"
        targetDistanceField.textColor = AppColor.UI.textPrimary
    }

    private func updateSaveButtonState() {
        let isEnabled = hasChanges()
        saveBarButtonItem.isEnabled = isEnabled
        saveBarButtonItem.tintColor = isEnabled ? RunningLevelManager.shared.accentUIColor : AppColor.UI.textTertiary
    }

    private func configureToolbar(_ toolbar: UIToolbar) {
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "완료", style: .done, target: self, action: #selector(confirmTargetDistanceSelection))
        ]
    }

    @objc private func confirmTargetDistanceSelection() {
        if selectedTargetDistanceMeters == nil,
           let firstDistance = DistanceOption.targetDistances.first {
            selectedTargetDistanceMeters = firstDistance
            updateTargetDistanceFieldText(for: firstDistance)
        }
        targetDistanceField.resignFirstResponder()
        updateSaveButtonState()
    }

    @objc private func saveButtonTapped() {
        let updatedShoe = makeEditedShoe()
        store.updateRegisteredShoe(updatedShoe)
        navigationController?.popViewController(animated: true)
    }
}

extension ShoeEditViewController: UITextFieldDelegate {
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

    func textFieldDidChangeSelection(_ textField: UITextField) {
        guard !isApplyingState else { return }
        if textField === nicknameField {
            refreshPreview()
            updateSaveButtonState()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        updateSaveButtonState()
        return true
    }
}

extension ShoeEditViewController: UIPickerViewDataSource, UIPickerViewDelegate {
    func numberOfComponents(in pickerView: UIPickerView) -> Int { 1 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        DistanceOption.targetDistances.count
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        let distance = DistanceOption.targetDistances[row]
        return "\(Int(distance / 1000.0)) km"
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        let distance = DistanceOption.targetDistances[row]
        selectedTargetDistanceMeters = distance
        updateTargetDistanceFieldText(for: distance)
        updateSaveButtonState()
    }
}

private final class ShoeEditPreviewView: HTView {
    private let shoeImageView = UIImageView()
    private let variantsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private var collectionHeightConstraint: Constraint?

    private var variants: [ShoeCatalogItem] = []
    private var currentShoe: RegisteredShoe?
    private var onSelectVariant: ((ShoeCatalogItem) -> Void)?
    private var imageTask: URLSessionDataTask?
    private var currentImageURL: String?

    override func configHierarchy() {
        [shoeImageView, variantsCollectionView, titleLabel, metaLabel].forEach { addSubview($0) }
    }

    override func configLayout() {
        shoeImageView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(220)
        }
        variantsCollectionView.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(20)
            self.collectionHeightConstraint = make.height.equalTo(60).constraint
        }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(variantsCollectionView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        metaLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview().inset(20)
        }
    }

    override func configView() {
        backgroundColor = AppColor.UI.cardBackground
        layer.cornerRadius = 24
        layer.borderWidth = 1
        layer.borderColor = AppColor.UI.border.cgColor

        shoeImageView.contentMode = .scaleAspectFit
        shoeImageView.backgroundColor = AppColor.UI.backgroundSecondary
        shoeImageView.layer.cornerRadius = 18
        shoeImageView.clipsToBounds = true
        shoeImageView.image = UIImage(systemName: "shoeprints.fill")
        shoeImageView.tintColor = AppColor.UI.textSecondary

        if let layout = variantsCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            layout.scrollDirection = .horizontal
            layout.minimumLineSpacing = 8
            layout.minimumInteritemSpacing = 8
        }
        variantsCollectionView.register(ShoeEditColorwayCell.self, forCellWithReuseIdentifier: ShoeEditColorwayCell.reuseID)
        variantsCollectionView.backgroundColor = .clear
        variantsCollectionView.showsHorizontalScrollIndicator = false
        variantsCollectionView.dataSource = self
        variantsCollectionView.delegate = self

        titleLabel.font = AppFont.UI.headlineSM
        titleLabel.textColor = AppColor.UI.textPrimary
        titleLabel.numberOfLines = 2

        metaLabel.font = AppFont.UI.bodyMD
        metaLabel.textColor = AppColor.UI.textSecondary
        metaLabel.numberOfLines = 3
    }

    func configure(
        with shoe: RegisteredShoe,
        variants: [ShoeCatalogItem],
        onSelectVariant: ((ShoeCatalogItem) -> Void)?
    ) {
        let previousSKU = currentShoe?.sku
        let didVariantsChange = self.variants != variants
        currentShoe = shoe
        self.variants = variants
        self.onSelectVariant = onSelectVariant

        titleLabel.text = shoe.displayName
        metaLabel.text = [shoe.brandName.uppercased(), shoe.modelName, shoe.colors.joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: "\n")

        let collectionHeight: CGFloat = variants.isEmpty ? 0 : 60
        collectionHeightConstraint?.update(offset: collectionHeight)
        variantsCollectionView.isHidden = variants.isEmpty
        if didVariantsChange {
            UIView.performWithoutAnimation {
                variantsCollectionView.reloadData()
                variantsCollectionView.layoutIfNeeded()
            }
        } else if previousSKU != shoe.sku {
            if let previousSKU,
               let previousIndex = variants.firstIndex(where: { $0.sku == previousSKU }) {
                updateSelectionAppearance(at: IndexPath(item: previousIndex, section: 0), isSelected: false)
            }
            if let currentIndex = variants.firstIndex(where: { $0.sku == shoe.sku }) {
                updateSelectionAppearance(at: IndexPath(item: currentIndex, section: 0), isSelected: true)
            }
        }

        if currentImageURL != shoe.imageURL {
            currentImageURL = shoe.imageURL
            imageTask?.cancel()
            imageTask = RemoteImageLoader.shared.loadImage(from: shoe.imageURL) { [weak self] image in
                self?.shoeImageView.image = image ?? UIImage(systemName: "shoeprints.fill")
                self?.shoeImageView.tintColor = AppColor.UI.textSecondary
            }
        }
    }

    private func updateSelectionAppearance(at indexPath: IndexPath, isSelected: Bool) {
        UIView.performWithoutAnimation {
            if let cell = variantsCollectionView.cellForItem(at: indexPath) as? ShoeEditColorwayCell {
                cell.setSelectedAppearance(isSelected)
            }
            variantsCollectionView.layoutIfNeeded()
        }
    }
}

extension ShoeEditPreviewView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        variants.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: ShoeEditColorwayCell.reuseID,
            for: indexPath
        ) as! ShoeEditColorwayCell
        let item = variants[indexPath.item]
        cell.configure(with: item, isSelected: item.sku == currentShoe?.sku)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard variants.indices.contains(indexPath.item) else { return }
        onSelectVariant?(variants[indexPath.item])
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        CGSize(width: 52, height: 52)
    }
}

private final class ShoeEditColorwayCell: HTCollectionViewCell {
    static let reuseID = "ShoeEditColorwayCell"

    private let imageView = UIImageView()
    private var imageTask: URLSessionDataTask?

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageView.image = UIImage(systemName: "shoeprints.fill")
    }

    override func configHierarchy() {
        contentView.addSubview(imageView)
    }

    override func configLayout() {
        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    override func configView() {
        contentView.layer.cornerRadius = 12
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = AppColor.UI.border.cgColor
        contentView.backgroundColor = AppColor.UI.cardBackground

        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = AppColor.UI.backgroundSecondary
        imageView.image = UIImage(systemName: "shoeprints.fill")
        imageView.tintColor = AppColor.UI.textSecondary
    }

    func configure(with item: ShoeCatalogItem, isSelected: Bool) {
        setSelectedAppearance(isSelected)
        imageTask = RemoteImageLoader.shared.loadImage(from: item.imageURL) { [weak self] image in
            self?.imageView.image = image ?? UIImage(systemName: "shoeprints.fill")
            self?.imageView.tintColor = AppColor.UI.textSecondary
        }
    }

    func setSelectedAppearance(_ isSelected: Bool) {
        contentView.layer.borderColor = isSelected ? RunningLevelManager.shared.accentUIColor.cgColor : AppColor.UI.border.cgColor
        contentView.layer.borderWidth = isSelected ? 2 : 1
    }
}
