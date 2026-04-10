//
//  ShoeDetailViewController.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import UIKit
import RxCocoa
import RxSwift
import SnapKit

final class ShoeDetailViewController: HTViewController {
    private enum DistanceOption {
        static let targetDistances: [Double] = stride(from: 100_000.0, through: 1_500_000.0, by: 100_000.0).map { $0 }
    }

    private let viewModel: ShoeDetailViewModel
    private let variantService: ShoeCatalogVariantServicing
    private let store: GearLocalStoring
    private let viewDidLoadSubject = PublishSubject<Void>()
    private let disposeBag = DisposeBag()

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let stackView = UIStackView()
    private let headerView: GearDetailHeaderView
    private let editCardView = HTView()
    private let nicknameTitleLabel = UILabel()
    private let nicknameField = UITextField()
    private let targetDistanceTitleLabel = UILabel()
    private let targetDistanceField = UITextField()
    private let saveEditsButton = UIButton(type: .system)
    private let statsCardView = GearStatsCardView()
    private let sessionsHeaderLabel = UILabel()
    private let sessionsStackView = UIStackView()
    private let emptySessionsLabel = UILabel()
    private let targetDistancePicker = UIPickerView()
    private let targetDistanceToolbar = UIToolbar()

    private var sessions: [GearLinkedSessionItem] = []
    private var currentViewData: ShoeDetailViewModel.ViewData?
    private var variants: [ShoeCatalogItem] = []
    private var selectedTargetDistanceMeters: Double?
    private var isApplyingViewData = false

    init(
        shoe: RegisteredShoe,
        variantService: ShoeCatalogVariantServicing = SupabaseShoeSearchService(),
        store: GearLocalStoring = GearLocalStore.shared
    ) {
        let viewModel = ShoeDetailViewModel(shoe: shoe)
        self.viewModel = viewModel
        self.variantService = variantService
        self.store = store
        self.headerView = GearDetailHeaderView(shoe: shoe)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
        viewDidLoadSubject.onNext(())
    }

    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)
        [nicknameTitleLabel, nicknameField, targetDistanceTitleLabel, targetDistanceField, saveEditsButton].forEach {
            editCardView.addSubview($0)
        }
        [headerView, editCardView, statsCardView, sessionsHeaderLabel, sessionsStackView, emptySessionsLabel].forEach {
            stackView.addArrangedSubview($0)
        }
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
            make.height.equalTo(52)
        }
        saveEditsButton.snp.makeConstraints { make in
            make.top.equalTo(targetDistanceField.snp.bottom).offset(20)
            make.leading.trailing.bottom.equalToSuperview().inset(20)
            make.height.equalTo(52)
        }
    }

    override func configView() {
        title = "운동화 상세"
        view.backgroundColor = AppColor.UI.backgroundGrouped

        stackView.axis = .vertical
        stackView.spacing = 18

        editCardView.backgroundColor = AppColor.UI.cardBackground
        editCardView.layer.cornerRadius = 24
        editCardView.layer.borderWidth = 1
        editCardView.layer.borderColor = AppColor.UI.border.cgColor

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
        configureToolbar(targetDistanceToolbar, action: #selector(confirmTargetDistanceSelection))

        saveEditsButton.setTitle("변경 저장", for: .normal)
        saveEditsButton.setTitleColor(.white, for: .normal)
        saveEditsButton.titleLabel?.font = AppFont.UI.buttonMD
        saveEditsButton.layer.cornerRadius = 16
        saveEditsButton.addTarget(self, action: #selector(saveEditsTapped), for: .touchUpInside)

        sessionsHeaderLabel.font = AppFont.UI.titleMD
        sessionsHeaderLabel.textColor = AppColor.UI.textPrimary
        sessionsHeaderLabel.text = "연결된 워크아웃"

        sessionsStackView.axis = .vertical
        sessionsStackView.spacing = 12

        emptySessionsLabel.font = AppFont.UI.bodyMD
        emptySessionsLabel.textColor = AppColor.UI.textSecondary
        emptySessionsLabel.text = "아직 연결된 워크아웃이 없습니다."
        emptySessionsLabel.numberOfLines = 0
        emptySessionsLabel.textAlignment = .center
        emptySessionsLabel.isHidden = true

        applySaveButtonStyle(isEnabled: false)
    }

    private func bind() {
        let output = viewModel.transform(
            input: .init(
                viewDidLoad: viewDidLoadSubject.asObservable()
            )
        )

        output.viewData
            .drive(onNext: { [weak self] viewData in
                self?.currentViewData = viewData
                self?.applyEditableFields(with: viewData.shoe)
                self?.headerView.configure(
                    with: viewData.shoe,
                    stats: viewData.stats,
                    variants: self?.variants ?? [],
                    onSelectVariant: { [weak self] item in
                        self?.updateColorway(to: item)
                    }
                )
                self?.statsCardView.configure(with: viewData.stats)
                self?.renderSessions(viewData.sessions)
                self?.fetchVariantsIfNeeded(for: viewData.shoe)
            })
            .disposed(by: disposeBag)

        output.showErrorMessage
            .emit(onNext: { [weak self] message in
                self?.showTransientMessage(message)
            })
            .disposed(by: disposeBag)
    }

    private func fetchVariantsIfNeeded(for shoe: RegisteredShoe) {
        guard !shoe.brandName.isEmpty, !shoe.modelName.isEmpty else { return }
        if !variants.isEmpty,
           variants.allSatisfy({ $0.brandName == shoe.brandName && $0.modelName == shoe.modelName }) {
            return
        }
        variantService.fetchVariants(brandName: shoe.brandName, modelName: shoe.modelName) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let items):
                self.variants = items
                if let viewData = self.currentViewData {
                    self.headerView.configure(
                        with: viewData.shoe,
                        stats: viewData.stats,
                        variants: items,
                        onSelectVariant: { [weak self] item in
                            self?.updateColorway(to: item)
                        }
                    )
                }
            case .failure:
                break
            }
        }
    }

    private func updateColorway(to item: ShoeCatalogItem) {
        guard var shoe = currentViewData?.shoe else { return }
        guard shoe.sku != item.sku else { return }
        shoe = RegisteredShoe(
            id: shoe.id,
            catalogID: item.id,
            nickname: shoe.nickname,
            brandName: item.brandName,
            modelName: item.modelName,
            sku: item.sku,
            colors: item.colors,
            imageURL: item.imageURL,
            createdAt: item.createdAt,
            registeredAt: shoe.registeredAt,
            targetDistanceMeters: shoe.targetDistanceMeters,
            initialDistanceMeters: shoe.initialDistanceMeters
        )
        store.updateRegisteredShoe(shoe)
    }

    private func applyEditableFields(with shoe: RegisteredShoe) {
        isApplyingViewData = true
        nicknameField.text = shoe.nickname
        selectedTargetDistanceMeters = shoe.targetDistanceMeters
        updateTargetDistanceFieldText(for: shoe.targetDistanceMeters)
        isApplyingViewData = false
        updateSaveButtonState()
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

    private func hasEditableChanges(for shoe: RegisteredShoe) -> Bool {
        let trimmedNickname = nicknameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedNickname = trimmedNickname.isEmpty ? nil : trimmedNickname
        let trimmedCurrentNickname = shoe.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let currentNickname = trimmedCurrentNickname.isEmpty ? nil : trimmedCurrentNickname
        return normalizedNickname != currentNickname || selectedTargetDistanceMeters != shoe.targetDistanceMeters
    }

    private func updateSaveButtonState() {
        let isEnabled = currentViewData.map { hasEditableChanges(for: $0.shoe) } ?? false
        saveEditsButton.isEnabled = isEnabled
        saveEditsButton.alpha = isEnabled ? 1.0 : 0.6
        applySaveButtonStyle(isEnabled: isEnabled)
    }

    private func applySaveButtonStyle(isEnabled: Bool) {
        let accentColor = RunningLevelManager.shared.accentUIColor
        saveEditsButton.backgroundColor = isEnabled ? accentColor : accentColor.withAlphaComponent(0.35)
    }

    private func configureToolbar(_ toolbar: UIToolbar, action: Selector) {
        toolbar.sizeToFit()
        toolbar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "완료", style: .done, target: self, action: action)
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

    @objc private func saveEditsTapped() {
        guard var shoe = currentViewData?.shoe else { return }
        let trimmedNickname = nicknameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        shoe = RegisteredShoe(
            id: shoe.id,
            catalogID: shoe.catalogID,
            nickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
            brandName: shoe.brandName,
            modelName: shoe.modelName,
            sku: shoe.sku,
            colors: shoe.colors,
            imageURL: shoe.imageURL,
            createdAt: shoe.createdAt,
            registeredAt: shoe.registeredAt,
            targetDistanceMeters: selectedTargetDistanceMeters ?? shoe.targetDistanceMeters,
            initialDistanceMeters: shoe.initialDistanceMeters
        )
        store.updateRegisteredShoe(shoe)
        view.endEditing(true)
    }

    private func renderSessions(_ sessions: [GearLinkedSessionItem]) {
        self.sessions = sessions
        sessionsStackView.arrangedSubviews.forEach { view in
            sessionsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        emptySessionsLabel.isHidden = !sessions.isEmpty
        sessionsStackView.isHidden = sessions.isEmpty

        sessions.forEach { session in
            let rowView = GearSessionRowView()
            rowView.configure(with: session)
            sessionsStackView.addArrangedSubview(rowView)
        }
    }

    private func showTransientMessage(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak alert] in
            alert?.dismiss(animated: true)
        }
    }
}

extension ShoeDetailViewController: UITextFieldDelegate {
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
        guard !isApplyingViewData else { return }
        if textField === nicknameField {
            updateSaveButtonState()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        updateSaveButtonState()
        return true
    }
}

extension ShoeDetailViewController: UIPickerViewDataSource, UIPickerViewDelegate {
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

private final class GearDetailHeaderView: HTView {
    private let shoeImageView = UIImageView()
    private let variantsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let brandLabel = UILabel()
    private let modelLabel = UILabel()
    private let metaLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var imageTask: URLSessionDataTask?
    private var variants: [ShoeCatalogItem] = []
    private var selectedSKU: String?
    private var currentImageURL: String?
    private var onSelectVariant: ((ShoeCatalogItem) -> Void)?
    private let shoe: RegisteredShoe

    init(shoe: RegisteredShoe) {
        self.shoe = shoe
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func configHierarchy() {
        [shoeImageView, variantsCollectionView, brandLabel, modelLabel, metaLabel, progressLabel, progressView].forEach { addSubview($0) }
    }

    override func configLayout() {
        shoeImageView.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(20)
            make.width.height.equalTo(116)
        }
        variantsCollectionView.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView.snp.bottom).offset(12)
            make.leading.equalTo(shoeImageView)
            make.width.equalTo(116)
            make.height.equalTo(60)
        }
        brandLabel.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView)
            make.leading.equalTo(shoeImageView.snp.trailing).offset(16)
            make.trailing.equalToSuperview().inset(20)
        }
        modelLabel.snp.makeConstraints { make in
            make.top.equalTo(brandLabel.snp.bottom).offset(6)
            make.leading.trailing.equalTo(brandLabel)
        }
        metaLabel.snp.makeConstraints { make in
            make.top.equalTo(modelLabel.snp.bottom).offset(10)
            make.leading.trailing.equalTo(brandLabel)
        }
        progressLabel.snp.makeConstraints { make in
            make.top.equalTo(variantsCollectionView.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(20)
        }
        progressView.snp.makeConstraints { make in
            make.top.equalTo(progressLabel.snp.bottom).offset(10)
            make.leading.trailing.bottom.equalToSuperview().inset(20)
            make.height.equalTo(10)
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
        variantsCollectionView.register(GearColorwayCell.self, forCellWithReuseIdentifier: GearColorwayCell.reuseID)
        variantsCollectionView.backgroundColor = .clear
        variantsCollectionView.showsHorizontalScrollIndicator = false
        variantsCollectionView.dataSource = self
        variantsCollectionView.delegate = self

        brandLabel.font = AppFont.UI.labelLG
        brandLabel.textColor = AppColor.UI.textSecondary

        modelLabel.font = AppFont.UI.headlineSM
        modelLabel.textColor = AppColor.UI.textPrimary
        modelLabel.numberOfLines = 2

        metaLabel.font = AppFont.UI.bodySM
        metaLabel.textColor = AppColor.UI.textSecondary
        metaLabel.numberOfLines = 2

        progressLabel.font = AppFont.UI.bodyMD
        progressLabel.textColor = AppColor.UI.textPrimary

        progressView.trackTintColor = AppColor.UI.systemGray6
        progressView.progressTintColor = AppColor.UI.primary
        progressView.layer.cornerRadius = 5
        progressView.clipsToBounds = true
    }

    func configure(
        with shoe: RegisteredShoe,
        stats: ShoeAggregateStats,
        variants: [ShoeCatalogItem],
        onSelectVariant: ((ShoeCatalogItem) -> Void)?
    ) {
        let previousSKU = selectedSKU
        let didVariantsChange = self.variants != variants
        self.variants = variants
        self.selectedSKU = shoe.sku
        self.onSelectVariant = onSelectVariant
        brandLabel.text = shoe.brandName.uppercased()
        modelLabel.text = shoe.displayName
        let modelLine = shoe.displayName == shoe.modelName ? shoe.modelName : "모델: \(shoe.modelName)"
        metaLabel.text = [modelLine, shoe.sku, shoe.colors.joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: "\n")
        if stats.overDistance > 0 {
            progressLabel.text = "\(AppFormatter.distance1f(stats.totalDistance)) / \(AppFormatter.distance1f(shoe.targetDistanceMeters)) · +\(AppFormatter.distance1f(stats.overDistance)) 초과"
        } else {
            progressLabel.text = "\(AppFormatter.distance1f(stats.totalDistance)) / \(AppFormatter.distance1f(shoe.targetDistanceMeters))"
        }
        progressView.progress = Float(stats.progress)
        if currentImageURL != shoe.imageURL {
            currentImageURL = shoe.imageURL
            imageTask?.cancel()
            imageTask = RemoteImageLoader.shared.loadImage(from: shoe.imageURL) { [weak self] image in
                self?.shoeImageView.image = image ?? UIImage(systemName: "shoeprints.fill")
                self?.shoeImageView.tintColor = AppColor.UI.textSecondary
            }
        }

        if didVariantsChange {
            UIView.performWithoutAnimation {
                variantsCollectionView.reloadData()
                variantsCollectionView.layoutIfNeeded()
            }
            return
        }

        guard previousSKU != shoe.sku else { return }
        var indexPathsToReload: [IndexPath] = []
        if let previousSKU,
           let previousIndex = variants.firstIndex(where: { $0.sku == previousSKU }) {
            indexPathsToReload.append(IndexPath(item: previousIndex, section: 0))
        }
        if let currentIndex = variants.firstIndex(where: { $0.sku == shoe.sku }) {
            indexPathsToReload.append(IndexPath(item: currentIndex, section: 0))
        }
        guard !indexPathsToReload.isEmpty else { return }
        UIView.performWithoutAnimation {
            variantsCollectionView.reloadItems(at: indexPathsToReload)
            variantsCollectionView.layoutIfNeeded()
        }
    }
}

extension GearDetailHeaderView: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        variants.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: GearColorwayCell.reuseID,
            for: indexPath
        ) as! GearColorwayCell
        let item = variants[indexPath.item]
        cell.configure(with: item, isSelected: item.sku == selectedSKU)
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

private final class GearColorwayCell: HTCollectionViewCell {
    static let reuseID = "GearColorwayCell"

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
        contentView.layer.borderColor = isSelected ? RunningLevelManager.shared.accentUIColor.cgColor : AppColor.UI.border.cgColor
        contentView.layer.borderWidth = isSelected ? 2 : 1
        imageTask = RemoteImageLoader.shared.loadImage(from: item.imageURL) { [weak self] image in
            self?.imageView.image = image ?? UIImage(systemName: "shoeprints.fill")
            self?.imageView.tintColor = AppColor.UI.textSecondary
        }
    }
}

private final class GearStatsCardView: HTView {
    private let distanceMetric = GearMetricView()
    private let durationMetric = GearMetricView()
    private let paceMetric = GearMetricView()

    override func configHierarchy() {
        [distanceMetric, durationMetric, paceMetric].forEach { addSubview($0) }
    }

    override func configLayout() {
        distanceMetric.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }
        durationMetric.snp.makeConstraints { make in
            make.top.equalTo(distanceMetric.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview()
        }
        paceMetric.snp.makeConstraints { make in
            make.top.equalTo(durationMetric.snp.bottom).offset(12)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    func configure(with stats: ShoeAggregateStats) {
        distanceMetric.configure(title: "총 거리", value: AppFormatter.distance1f(stats.totalDistance))
        durationMetric.configure(title: "총 시간", value: GearFormatters.duration(stats.totalDuration))
        paceMetric.configure(title: "평균 페이스", value: GearFormatters.pace(stats.averagePace))
    }
}

private final class GearMetricView: HTView {
    private let cardView = HTView()
    private let titleLabel = UILabel()
    private let valueLabel = UILabel()

    override func configHierarchy() {
        addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(valueLabel)
    }

    override func configLayout() {
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.top.leading.bottom.equalToSuperview().inset(16)
        }
        valueLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(16)
        }
    }

    override func configView() {
        cardView.backgroundColor = AppColor.UI.cardBackground
        cardView.layer.cornerRadius = 18
        cardView.layer.borderWidth = 1
        cardView.layer.borderColor = AppColor.UI.border.cgColor

        titleLabel.font = AppFont.UI.bodyMD
        titleLabel.textColor = AppColor.UI.textSecondary

        valueLabel.font = AppFont.UI.metricLabel
        valueLabel.textColor = AppColor.UI.textPrimary
    }

    func configure(title: String, value: String) {
        titleLabel.text = title
        valueLabel.text = value
    }
}

private final class GearSessionRowView: HTView {
    private let button = UIButton(type: .system)
    private let kindLabel = UILabel()
    private let dateLabel = UILabel()
    private let valueLabel = UILabel()

    override func configHierarchy() {
        addSubview(button)
        [kindLabel, dateLabel, valueLabel].forEach { button.addSubview($0) }
    }

    override func configLayout() {
        button.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        kindLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualTo(valueLabel.snp.leading).offset(-12)
        }
        dateLabel.snp.makeConstraints { make in
            make.top.equalTo(kindLabel.snp.bottom).offset(6)
            make.leading.bottom.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualTo(valueLabel.snp.leading).offset(-12)
        }
        valueLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(16)
        }
    }

    override func configView() {
        button.backgroundColor = AppColor.UI.cardBackground
        button.layer.cornerRadius = 18
        button.layer.borderWidth = 1
        button.layer.borderColor = AppColor.UI.border.cgColor
        button.isUserInteractionEnabled = false

        kindLabel.font = AppFont.UI.titleSM
        kindLabel.textColor = AppColor.UI.textPrimary

        dateLabel.font = AppFont.UI.bodySM
        dateLabel.textColor = AppColor.UI.textSecondary

        valueLabel.font = AppFont.UI.metricCaption
        valueLabel.textColor = AppColor.UI.textPrimary
        valueLabel.numberOfLines = 2
        valueLabel.textAlignment = .right
    }

    func configure(with session: GearLinkedSessionItem) {
        kindLabel.text = session.title
        dateLabel.text = AppFormatter.recordDate.string(from: session.startedAt)
        valueLabel.text = "\(AppFormatter.distance1f(session.distance))\n\(GearFormatters.duration(session.duration))"
    }
}
