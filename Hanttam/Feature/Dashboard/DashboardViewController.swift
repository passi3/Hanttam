//
//  DashboardViewController.swift
//  Hanttam
//
//  Created by passi on 3/25/26.
//

import UIKit
import SwiftUI
import RxSwift
import RxCocoa
import SnapKit

final class DashboardViewController: HTViewController {
    
    private let viewModel          = DashboardViewModel()
    private let disposeBag         = DisposeBag()
    private let viewDidLoadTrigger = PublishSubject<Void>()
    
    // MARK: - Colors (sPQ7E style)

    private let bgColor = AppColor.UI.dashboardBg
    private let secondaryBg = AppColor.UI.dashboardSecondaryBg
    private let textDark = AppColor.UI.dashboardTextDark
    private let textGray = AppColor.UI.dashboardTextGray
    
    // MARK: - Subviews
    
    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator   = false
        sv.contentInsetAdjustmentBehavior = .always
        return sv
    }()
    
    private let contentStack: UIStackView = {
        let s = UIStackView()
        s.axis    = .vertical
        s.spacing = 24
        return s
    }()
    
    private let headerLabel: UILabel = {
        let l = UILabel()
        l.text = "PERFORMANCE INSIGHTS"
        l.font = AppFont.UI.labelLG
        l.textColor = AppColor.UI.textSecondary
        return l
    }()
    
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Analytics"
        l.font = AppFont.UI.displaySM
        l.textColor = AppColor.UI.textPrimary
        return l
    }()
    
    private var chartHostController   : UIHostingController<CumulativeChartView>?
    private var calendarHostController: UIHostingController<WorkoutCalendarView>?
    private var runningGradeView = RunningGradeView()
    
    //MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        bind()
        viewDidLoadTrigger.onNext(())
    }
    
    //MARK: - ConfigUI
    
    private func setupNavigationBar() {
        navigationController?.navigationBar.prefersLargeTitles = false
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor.white.withAlphaComponent(0.92)
        appearance.titleTextAttributes = [
            .font: AppFont.UI.titleMD,
            .foregroundColor: textDark
        ]
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
    }
    
    override func configHierarchy() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
    }
    override func configLayout() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentStack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(32)
            make.horizontalEdges.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(120)
            make.width.equalToSuperview().offset(-48)
        }
    }
    override func configView() {
        title = "한땀"
        view.backgroundColor = AppColor.UI.dashboardBg
        let headerStack     = UIStackView(arrangedSubviews: [headerLabel, titleLabel])
        headerStack.axis    = .vertical
        headerStack.spacing = 8
        contentStack.addArrangedSubview(headerStack)
        
        let chartPlaceholder = UIView()
        chartPlaceholder.tag = 100
        contentStack.addArrangedSubview(chartPlaceholder)
        
        let calendarPlaceholder = UIView()
        calendarPlaceholder.tag = 200
        contentStack.addArrangedSubview(calendarPlaceholder)
        
        contentStack.addArrangedSubview(runningGradeView)
        contentStack.spacing = 20
        
        headerStack.layer.shadowPath = UIBezierPath(rect: headerStack.bounds).cgPath
        headerStack.layer.shadowOpacity = 0.8
        chartPlaceholder.layer.shadowPath = UIBezierPath(rect: chartPlaceholder.bounds).cgPath
        chartPlaceholder.layer.shadowOpacity = 0.8
        calendarPlaceholder.layer.shadowPath = UIBezierPath(rect: calendarPlaceholder.bounds).cgPath
        calendarPlaceholder.layer.shadowOpacity = 0.8
    }
    
    private func bind() {
        let input  = DashboardViewModel.Input(viewDidLoad: viewDidLoadTrigger.asObservable())
        let output = viewModel.transform(input: input)
        
        output.level
            .drive(onNext: { [weak self] level in
                let color = level.gradeColor
                self?.headerLabel.textColor = color
            })
            .disposed(by: disposeBag)
        
        // 누적 차트
        Driver.combineLatest(
            output.thisMonthDaily,
            output.lastMonthDaily,
            output.thisMonthTotal,
            output.lastMonthTotal,
            output.level
        )
        .drive(onNext: { [weak self] thisDaily, lastDaily, thisTotal, lastTotal, level in
            self?.updateChart(thisDaily: thisDaily, lastDaily: lastDaily,
                              thisTotal: thisTotal, lastToal: lastTotal, accentColor: level.swiftUIColor)
        })
        .disposed(by: disposeBag)
        
        // 캘린더
        Driver.combineLatest(output.calendarData, output.level)
            .drive(onNext: { [weak self] data, level in
                self?.updateCalendar(data: data, accentColor: level.swiftUIColor)
            })
            .disposed(by: disposeBag)
        
        // 등급뷰
        Driver.combineLatest(
            output.level,
            output.totalDistance,
            output.progress,
            output.remainingDist
        )
        .drive(onNext: { [weak self] level, total, progress, remaining in
            self?.runningGradeView.configure(level: level, totalDistance: total,
                                             progress: progress, remainingDistance: remaining)
        })
        .disposed(by: disposeBag)
        
        runningGradeView.tapEvent
            .subscribe(onNext: { [weak self] in
                    let vc = RunningLevelViewController()
                vc.title = "러닝 등급"
                self?.navigationController?.pushViewController(vc, animated: true)
            })
            .disposed(by: disposeBag)
    }
    
    //MARK: - Update
    private func updateChart(thisDaily: [DailyCumulativeDistance],
                             lastDaily: [DailyCumulativeDistance],
                             thisTotal: Double, lastToal: Double, accentColor: Color) {
        chartHostController?.willMove(toParent: nil)
        chartHostController?.view.removeFromSuperview()
        chartHostController?.removeFromParent()
        
        if let ph = contentStack.viewWithTag(100) {
            ph.removeFromSuperview()
        }
        
        let chartView = CumulativeChartView(
            thisMonthDist: thisDaily,
            lastMonthDist: lastDaily,
            thisMonthTotal: thisTotal,
            lastMonthTotal: lastToal,
            accentColor: accentColor
        )
        let host = UIHostingController(rootView: chartView)
        host.view.backgroundColor = .clear
        
        addChild(host)
        contentStack.insertArrangedSubview(host.view, at: 1)
        host.didMove(toParent: self)
        chartHostController = host
    }
    
    private func updateCalendar(data: [Date: DailyWorkoutInfo], accentColor: Color) {
        calendarHostController?.willMove(toParent: nil)
        calendarHostController?.view.removeFromSuperview()
        calendarHostController?.removeFromParent()
        
        if let ph = contentStack.viewWithTag(200) {
            ph.removeFromSuperview()
        }
        
        let calendarView = WorkoutCalendarView(dailyData: data, accentColor: accentColor)
        let host = UIHostingController(rootView: calendarView)
        host.view.backgroundColor = .clear
        
        addChild(host)
        
        let insertIndex: Int
        if let gradeIndex = contentStack.arrangedSubviews.firstIndex(of: runningGradeView) {
            insertIndex = gradeIndex
        } else {
            insertIndex = contentStack.arrangedSubviews.count
        }
        contentStack.insertArrangedSubview(host.view, at: insertIndex)
        host.didMove(toParent: self)
        calendarHostController = host
    }
}
