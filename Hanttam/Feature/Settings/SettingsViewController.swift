//
//  SettingsViewController.swift
//  Hanttam
//
//  Created by passi on 4/19/26.
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class SettingsViewController: HTViewController {

    // MARK: - Section

    private enum Section: Int, CaseIterable {
        case permissions
        case voice
        case appInfo
    }

    // MARK: - Properties

    private let viewModel: SettingsViewModel
    private let viewWillAppearSubject = PublishSubject<Void>()
    private let selectPermissionSubject = PublishSubject<SettingsViewModel.PermissionKind>()
    private let disposeBag = DisposeBag()

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var permissionItems: [SettingsViewModel.PermissionItem] = []
    private var appVersion: String = "-"
    private var voiceAnnouncementsEnabled = WorkoutVoiceAnnouncementPreferences.isEnabled

    // MARK: - Init

    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        bind()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppearSubject.onNext(())
    }

    // MARK: - Setup

    override func configHierarchy() {
        view.addSubview(tableView)
    }

    override func configLayout() {
        tableView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }
    }

    override func configView() {
        title = "설정"
        view.backgroundColor = AppColor.UI.backgroundGrouped

        tableView.register(SettingsPermissionCell.self, forCellReuseIdentifier: SettingsPermissionCell.reuseID)
        tableView.register(SettingsSwitchCell.self, forCellReuseIdentifier: SettingsSwitchCell.reuseID)
        tableView.register(SettingsInfoCell.self, forCellReuseIdentifier: SettingsInfoCell.reuseID)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = AppColor.UI.backgroundGrouped
    }

    // MARK: - Binding

    private func bind() {
        let output = viewModel.transform(
            input: .init(
                viewWillAppear: viewWillAppearSubject.asObservable(),
                selectPermission: selectPermissionSubject.asObservable()
            )
        )

        output.permissions
            .drive(onNext: { [weak self] items in
                self?.permissionItems = items
                self?.tableView.reloadData()
            })
            .disposed(by: disposeBag)

        output.appVersion
            .drive(onNext: { [weak self] version in
                self?.appVersion = version
            })
            .disposed(by: disposeBag)

        output.openDestination
            .emit(onNext: { destination in
                let urlString: String
                switch destination {
                case .healthApp:
                    urlString = "x-apple-health://"
                case .locationSettings:
                    urlString = UIApplication.openSettingsURLString
                case .notificationSettings:
                    urlString = UIApplication.openNotificationSettingsURLString
                }
                guard let url = URL(string: urlString) else { return }
                UIApplication.shared.open(url)
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .permissions: return permissionItems.count
        case .voice:       return 1
        case .appInfo:     return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .permissions: return "권한"
        case .voice:       return "운동"
        case .appInfo:     return "앱 정보"
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .permissions:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsPermissionCell.reuseID, for: indexPath
            ) as! SettingsPermissionCell
            cell.configure(with: permissionItems[indexPath.row])
            return cell

        case .voice:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsSwitchCell.reuseID, for: indexPath
            ) as! SettingsSwitchCell
            cell.configure(
                title: "운동 음성 안내",
                iconName: "speaker.wave.2.fill",
                isOn: voiceAnnouncementsEnabled
            ) { [weak self] isOn in
                guard let self else { return }
                self.voiceAnnouncementsEnabled = isOn
                WatchBridge.shared.sendVoiceAnnouncementsEnabled(isOn)
            }
            return cell

        case .appInfo:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsInfoCell.reuseID, for: indexPath
            ) as! SettingsInfoCell
            cell.configure(title: "버전", detail: appVersion)
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard Section(rawValue: indexPath.section) == .permissions else { return }
        selectPermissionSubject.onNext(permissionItems[indexPath.row].kind)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 56 }
}

// MARK: - SettingsSwitchCell

private final class SettingsSwitchCell: HTTableViewCell {
    static let reuseID = "SettingsSwitchCell"

    private let iconBackgroundView = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let toggle = UISwitch()
    private var onToggle: ((Bool) -> Void)?

    override func prepareForReuse() {
        super.prepareForReuse()
        onToggle = nil
    }

    override func configHierarchy() {
        [iconBackgroundView, titleLabel, toggle].forEach { contentView.addSubview($0) }
        iconBackgroundView.addSubview(iconImageView)
    }

    override func configLayout() {
        iconBackgroundView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(32)
        }
        iconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(18)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconBackgroundView.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(toggle.snp.leading).offset(-12)
        }
        toggle.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
    }

    override func configView() {
        backgroundColor = .white
        selectionStyle = .none

        iconBackgroundView.layer.cornerRadius = 8
        iconBackgroundView.clipsToBounds = true
        iconBackgroundView.backgroundColor = AppColor.UI.primary

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .white

        titleLabel.font = AppFont.UI.bodyLG
        titleLabel.textColor = AppColor.UI.textPrimary

        toggle.onTintColor = AppColor.UI.primary
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
    }

    func configure(title: String, iconName: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) {
        titleLabel.text = title
        iconImageView.image = UIImage(systemName: iconName)
        toggle.isOn = isOn
        self.onToggle = onToggle
    }

    @objc private func toggleChanged() {
        onToggle?(toggle.isOn)
    }
}

// MARK: - SettingsPermissionCell

private final class SettingsPermissionCell: HTTableViewCell {
    static let reuseID = "SettingsPermissionCell"

    private let iconBackgroundView = UIView()
    private let iconImageView = UIImageView()
    private let titleLabel = UILabel()
    private let statusBadge = UILabel()

    override func configHierarchy() {
        [iconBackgroundView, titleLabel, statusBadge].forEach { contentView.addSubview($0) }
        iconBackgroundView.addSubview(iconImageView)
    }

    override func configLayout() {
        iconBackgroundView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(32)
        }
        iconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(18)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(iconBackgroundView.snp.trailing).offset(12)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(statusBadge.snp.leading).offset(-8)
        }
        statusBadge.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(36)
            make.centerY.equalToSuperview()
        }
    }

    override func configView() {
        backgroundColor = .white
        selectionStyle = .default
        accessoryType = .disclosureIndicator

        iconBackgroundView.layer.cornerRadius = 8
        iconBackgroundView.clipsToBounds = true

        iconImageView.contentMode = .scaleAspectFit
        iconImageView.tintColor = .white

        titleLabel.font = AppFont.UI.bodyLG
        titleLabel.textColor = AppColor.UI.textPrimary

        statusBadge.font = AppFont.UI.labelMD
        statusBadge.layer.cornerRadius = 5
        statusBadge.clipsToBounds = true
        statusBadge.textAlignment = .center
    }

    func configure(with item: SettingsViewModel.PermissionItem) {
        titleLabel.text = item.kind.title
        iconImageView.image = UIImage(systemName: item.kind.iconName)

        let iconTint: UIColor = switch item.kind {
        case .healthKit:    UIColor(red: 1, green: 0.18, blue: 0.33, alpha: 1)
        case .location:     AppColor.UI.primary
        case .notification: AppColor.UI.warning
        }
        iconBackgroundView.backgroundColor = iconTint

        statusBadge.text = "  \(item.status.label)  "
        switch item.status {
        case .authorized:
            statusBadge.backgroundColor = AppColor.UI.success.withAlphaComponent(0.15)
            statusBadge.textColor = AppColor.UI.success
        case .denied:
            statusBadge.backgroundColor = AppColor.UI.red.withAlphaComponent(0.12)
            statusBadge.textColor = AppColor.UI.red
        case .notDetermined, .unavailable:
            statusBadge.backgroundColor = AppColor.UI.textTertiary.withAlphaComponent(0.15)
            statusBadge.textColor = AppColor.UI.textTertiary
        }
    }
}

// MARK: - SettingsInfoCell

private final class SettingsInfoCell: HTTableViewCell {
    static let reuseID = "SettingsInfoCell"

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override func configHierarchy() {
        [titleLabel, detailLabel].forEach { contentView.addSubview($0) }
    }

    override func configLayout() {
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
        detailLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
    }

    override func configView() {
        backgroundColor = .white
        selectionStyle = .none

        titleLabel.font = AppFont.UI.bodyLG
        titleLabel.textColor = AppColor.UI.textPrimary

        detailLabel.font = AppFont.UI.bodyLG
        detailLabel.textColor = AppColor.UI.textSecondary
    }

    func configure(title: String, detail: String) {
        titleLabel.text = title
        detailLabel.text = detail
    }
}
