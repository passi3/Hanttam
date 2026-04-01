//
//  RecordsViewController.swift
//  Hanttam
//
//  Created by passi on 3/25/26.
//

import UIKit
import SwiftUI
import MapKit
import RxCocoa
import RxSwift
import SnapKit

final class RecordsViewController: HTViewController {
    
    private enum Section: Hashable {
        case intervalRecords
        case records
        case showMore
    }

    private enum Item: Hashable {
        case interval(IntervalRecord)
        case record(RunningRecord)
        case showMore
    }
    
    private let viewModel = RecordsViewModel()
    private let viewDidLoadSubject = PublishSubject<Void>()
    private let refreshSubject = PublishSubject<Void>()
    private let selectRecordSubject = PublishSubject<Int>()
    private let disposeBag = DisposeBag()

    private var allRecords: [RunningRecord] = []
    private var records: [RunningRecord] = []
    private var intervalRecords: [IntervalRecord] = []
    private var routeSnapshots: [Date: UIImage] = [:]
    private var failedRouteDates = Set<Date>()

    private let initialDisplayCount = 5
    private var isExpanded = false

    private var dataSource: UITableViewDiffableDataSource<Section, Item>!

    private let tableView = UITableView(frame: .zero, style: .plain)
    private var chartHosting: UIHostingController<RunningChartView>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configHierarchy()
        configLayout()
        configView()
        
        setupDataSource()
        bind()
        viewDidLoadSubject.onNext(())
    }

    // MARK: - UI Configuration

    override func configHierarchy() {
        let chartView = RunningChartView(store: viewModel)
        let hosting = UIHostingController(rootView: chartView)
        chartHosting = hosting

        addChild(hosting)
        hosting.view.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 320)
        hosting.didMove(toParent: self)

        tableView.tableHeaderView = hosting.view
        view.addSubview(tableView)
    }

    override func configLayout() {
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func configView() {
        title = "러닝 기록"
        navigationController?.navigationBar.tintColor = RunningLevelManager.shared.accentUIColor
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "photo.badge.plus"),
            style: .plain,
            target: self,
            action: #selector(shareChartTapped)
        )

        chartHosting?.view.backgroundColor = AppColor.UI.backgroundPrimary

        tableView.register(RecordCell.self, forCellReuseIdentifier: RecordCell.id)
        tableView.rowHeight = 88
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        tableView.delegate = self
        tableView.clipsToBounds = true

        let refreshControl = UIRefreshControl()
        tableView.refreshControl = refreshControl
        
        refreshControl.rx.controlEvent(.valueChanged)
            .bind(to: refreshSubject)
            .disposed(by: disposeBag)
    }

    // MARK: - DataSource

    private func setupDataSource() {
        dataSource = UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let self else { return UITableViewCell() }
            switch item {
            case .showMore:
                let cell = UITableViewCell()
                cell.selectionStyle = .none
                var config = cell.defaultContentConfiguration()
                config.text = "더보기"
                config.textProperties.alignment = .center
                config.textProperties.color = AppColor.UI.systemBlue
                config.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
                cell.contentConfiguration = config
                return cell

            case .interval(let interval):
                let cell = tableView.dequeueReusableCell(withIdentifier: RecordCell.id, for: indexPath) as! RecordCell
                cell.configureInterval(with: interval, dateFormatter: AppFormatter.recordDate)
                return cell

            case .record(let record):
                let cell = tableView.dequeueReusableCell(withIdentifier: RecordCell.id, for: indexPath) as! RecordCell
                cell.configure(with: record, dateFormatter: AppFormatter.recordDate)
                self.loadRouteImage(for: record, into: cell, at: indexPath)
                return cell
            }
        }
    }

    private func applySnapshot(animated: Bool = true) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()

        // Interval records section
        if !intervalRecords.isEmpty {
            snapshot.appendSections([.intervalRecords])
            snapshot.appendItems(intervalRecords.map { .interval($0) }, toSection: .intervalRecords)
        }

        snapshot.appendSections([.records])
        let displayed = isExpanded ? records : Array(records.prefix(initialDisplayCount))
        snapshot.appendItems(displayed.map { .record($0) }, toSection: .records)

        if !isExpanded && records.count > initialDisplayCount {
            snapshot.appendSections([.showMore])
            snapshot.appendItems([.showMore], toSection: .showMore)
        }

        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    // MARK: - Bind

    private func bind() {
        let input = RecordsViewModel.Input(
            viewDidLoad: viewDidLoadSubject.asObservable(),
            refresh: refreshSubject.asObservable(),
            selectRecord: selectRecordSubject.asObservable()
        )
        let output = viewModel.transform(input: input)

        // 전체 기록 로드 완료 시 캐시 초기화
        output.records
            .drive(onNext: { [weak self] records in
                guard let self else { return }
                self.allRecords = records
                self.routeSnapshots.removeAll()
                self.failedRouteDates.removeAll()
            })
            .disposed(by: disposeBag)

        // 필터링된 기록으로 테이블 갱신 (period/offset 변경 포함)
        output.filteredRecords
            .drive(onNext: { [weak self] records in
                guard let self else { return }
                self.records = records
                self.intervalRecords = IntervalStore.shared.fetchAll()
                self.isExpanded = false
                self.applySnapshot(animated: true)
            })
            .disposed(by: disposeBag)

        output.isLoading
            .drive(onNext: { [weak self] loading in
                if !loading { self?.tableView.refreshControl?.endRefreshing() }
            })
            .disposed(by: disposeBag)

        output.selectedRecord
            .drive(onNext: { [weak self] record in
                self?.navigateToDetail(record)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Navigation

    private func navigateToDetail(_ record: RunningRecord) {
        let vc = RunDetailViewController()
        present(vc, animated: true)
    }

    // MARK: - Actions

    @objc private func shareChartTapped() {
        let dist = allRecords.reduce(0) { $0 + $1.distance } / 1000
        let runs = allRecords.count

        let shareView = ChartPhotoShareView {
            RecordsShareOverlay(
                period: self.viewModel.period,
                offset: self.viewModel.offset,
                chartRecords: self.viewModel.records,
                totalDistance: dist,
                totalRuns: runs
            )
        }
        let vc = UIHostingController(rootView: shareView)
        vc.view.backgroundColor = AppColor.UI.backgroundGrouped
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(vc, animated: true)
    }

    // MARK: - Route Snapshot

    private func loadRouteImage(for record: RunningRecord, into cell: RecordCell, at indexPath: IndexPath) {
        guard !record.isIndoor else { return }
        if let cached = routeSnapshots[record.date] {
            cell.setRouteImage(cached)
            return
        }
        if failedRouteDates.contains(record.date) {
            cell.setRouteImage(nil)
            return
        }
        cell.setRouteImage(nil)
        guard let workout = record.workout else {
            failedRouteDates.insert(record.date)
            return
        }
        let recordDate = record.date
        HealthKitStore.shared.fetchAltitudeData(for: workout) { [weak self] points in
            guard let self, points.count >= 2 else {
                self?.failedRouteDates.insert(recordDate)
                return
            }
            let image = self.generateRouteSnapshot(from: points)
            if let image {
                self.routeSnapshots[recordDate] = image
                if let visibleCell = self.tableView.cellForRow(at: indexPath) as? RecordCell {
                    visibleCell.setRouteImage(image)
                }
            } else {
                self.failedRouteDates.insert(recordDate)
            }
        }
    }

    private func generateRouteSnapshot(from points: [AltitudePoint]) -> UIImage? {
        let coords = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return nil }

        let size = CGSize(width: 60, height: 60)
        let padding: CGFloat = 6
        let drawSize = CGSize(width: size.width - padding * 2,
                              height: size.height - padding * 2)
        let latRange = maxLat - minLat
        let lngRange = maxLng - minLng
        let scale = latRange > 0 || lngRange > 0
            ? min(drawSize.width / max(lngRange, 1e-6), drawSize.height / max(latRange, 1e-6))
            : 1.0

        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            for (i, coord) in coords.enumerated() {
                let x = padding + (coord.longitude - minLng) * scale
                let y = padding + (maxLat - coord.latitude) * scale
                let point = CGPoint(x: x, y: y)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            RunningLevelManager.shared.accentUIColor.setStroke()
            path.lineWidth = 3
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
}

// MARK: - UITableViewDelegate

extension RecordsViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .showMore:
            isExpanded = true
            applySnapshot()
        case .interval(let interval):
            let vc = RunDetailViewController()
            present(vc, animated: true)
        case .record(let record):
            if let index = records.firstIndex(of: record) {
                selectRecordSubject.onNext(index)
            }
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let item = dataSource.itemIdentifier(for: indexPath),
              case .record(let record) = item else { return nil }

        let deleteAction = UIContextualAction(style: .destructive, title: "삭제") { [weak self] _, _, done in
            self?.confirmDelete(record: record, completion: done)
        }
        deleteAction.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [deleteAction])
    }

    private func confirmDelete(record: RunningRecord, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(
            title: "운동 기록 삭제",
            message: "이 기록을 헬스킷에서 영구 삭제합니다.\n되돌릴 수 없습니다.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "삭제", style: .destructive) { [weak self] _ in
            self?.viewModel.deleteRecord(record) { success, error in
                if success {
                    completion(true)
                } else {
                    completion(false)
                    let msg = error?.localizedDescription ?? "이 앱에서 생성한 기록만 삭제할 수 있습니다."
                    let errAlert = UIAlertController(title: "삭제 실패", message: msg, preferredStyle: .alert)
                    errAlert.addAction(UIAlertAction(title: "확인", style: .default))
                    self?.present(errAlert, animated: true)
                }
            }
        })
        present(alert, animated: true)
    }
}

// MARK: - Records Share Overlay

private struct RecordsShareOverlay: View {
    let period: ChartPeriod
    let offset: Int
    let chartRecords: [RunningRecord]
    let totalDistance: Double
    let totalRuns: Int

    @Environment(\.overlayTextColor) private var textColor
    @Environment(\.overlaySubTextColor) private var subTextColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                // summaryLabel(value: String(format: "%.1f", totalDistance), unit: "km", caption: "총 거리")
                // summaryLabel(value: "\(totalRuns)", unit: "회", caption: "총 러닝")
            }
            RunningChartShareView(records: chartRecords, period: period, offset: offset)
        }
    }

    private func summaryLabel(value: String, unit: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundStyle(textColor)
                Text(unit).font(.caption).foregroundStyle(subTextColor)
            }
            Text(caption).font(.caption2).foregroundStyle(subTextColor)
        }
    }
}

// MARK: - Cell

private class RecordCell: UITableViewCell {

    static let id = "RecordCell"

    private let dateLabel = UILabel()
    private let sourceLabel = UILabel()
    private let distanceLabel = UILabel()
    private let detailStack = UIStackView()
    private let durationLabel = UILabel()
    private let caloriesLabel = UILabel()
    private let routeImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.backgroundColor = AppColor.UI.tertiarySystemFill
        return iv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .default
        accessoryType = .disclosureIndicator
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        routeImageView.image = nil
        routeImageView.contentMode = .scaleAspectFill
        routeImageView.tintColor = nil
        routeImageView.backgroundColor = AppColor.UI.tertiarySystemFill
        sourceLabel.textColor = AppColor.UI.textTertiary
    }

    private func setupUI() {
        dateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        dateLabel.textColor = AppColor.UI.textSecondary

        // 소스 라벨 스타일
        sourceLabel.font = .systemFont(ofSize: 11, weight: .regular)
        sourceLabel.textColor = AppColor.UI.textTertiary

        distanceLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .light)

        durationLabel.font = .systemFont(ofSize: 13)
        durationLabel.textColor = AppColor.UI.textSecondary

        caloriesLabel.font = .systemFont(ofSize: 13)
        caloriesLabel.textColor = AppColor.UI.textSecondary

        detailStack.axis = .horizontal
        detailStack.spacing = 12
        detailStack.addArrangedSubview(durationLabel)
        detailStack.addArrangedSubview(caloriesLabel)

        // 상단 날짜와 소스를 가로로 배치
        let topStack = UIStackView(arrangedSubviews: [dateLabel, sourceLabel, UIView()])
        topStack.axis = .horizontal
        topStack.spacing = 8
        topStack.alignment = .firstBaseline

        let vStack = UIStackView(arrangedSubviews: [topStack, distanceLabel, detailStack])
        vStack.axis = .vertical
        vStack.spacing = 2

        contentView.addSubview(vStack)
        contentView.addSubview(routeImageView)

        routeImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(20)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(60)
        }

        vStack.snp.makeConstraints { make in
            make.leading.equalTo(routeImageView.snp.trailing).offset(12)
            make.trailing.equalToSuperview().offset(-12)
            make.centerY.equalToSuperview()
        }
    }

    func configure(with record: RunningRecord, dateFormatter: DateFormatter) {
        dateLabel.text = dateFormatter.string(from: record.date)

        // 실내/실외 태그 + 소스 정보
        let tag = record.isIndoor ? "실내" : "실외"
        let source: String
        if let dev = record.deviceName {
            source = "\(tag) • \(record.sourceName) • \(dev)"
        } else {
            source = "\(tag) • \(record.sourceName)"
        }
        sourceLabel.text = source

        if record.isIndoor {
            let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .light)
            routeImageView.image = UIImage(systemName: "figure.run.treadmill", withConfiguration: config)
            routeImageView.tintColor = RunningLevelManager.shared.accentUIColor.withAlphaComponent(0.6)
            routeImageView.contentMode = .center
            routeImageView.backgroundColor = RunningLevelManager.shared.accentUIColor.withAlphaComponent(0.08)
        }

        distanceLabel.text = AppFormatter.distance2f(record.distance)
        durationLabel.text = AppFormatter.duration(record.duration)
        caloriesLabel.text = AppFormatter.calories(record.calories)
    }

    func configureInterval(with record: IntervalRecord, dateFormatter: DateFormatter) {
        dateLabel.text = dateFormatter.string(from: record.date)
        sourceLabel.text = "INTERVAL"
        sourceLabel.textColor = RunningLevelManager.shared.accentUIColor
        distanceLabel.text = AppFormatter.distance2f(record.totalDistance)
        durationLabel.text = AppFormatter.duration(record.totalDuration)
        caloriesLabel.text = "\(record.settings.sets)세트 · \(Int(record.settings.lapDistance))m"
    }

    func setRouteImage(_ image: UIImage?) {
        routeImageView.image = image
    }
}
