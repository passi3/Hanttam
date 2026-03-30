//
//  RunningGradeView.swift
//  Hanttam
//
//  Created by passi on 3/30/26.
//

import UIKit
import RxCocoa
import RxSwift
import SnapKit

final class RunningGradeView: HTView {
    
    let tapEvent: ControlEvent<Void>
    
    //MARK: - Subviews
    
    private let iconContainer: UIView = {
        let v = UIView()
        v.backgroundColor    = AppColor.UI.dashboardSecondaryBg
        v.layer.cornerRadius = 32
        return v
    }()
    
    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        return iv
    }()
    
    private let chevronView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "chevron.right")?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
        iv.tintColor   = AppColor.UI.textTertiary.withAlphaComponent(0.5)
        iv.contentMode = .scaleAspectFit
        return iv
    }()
    
    private let levelLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 10, weight: .heavy)
        return l
    }()
    
    private let totalLabel: UILabel = {
        let l = UILabel()
        l.font      = .systemFont(ofSize: 36, weight: .black)
        l.textColor = AppColor.UI.textPrimary
        return l
    }()
    
    private let unitLabel: UILabel = {
        let l = UILabel()
        l.font      = .systemFont(ofSize: 14, weight: .bold)
        l.textColor = AppColor.UI.textSecondary
        return l
    }()
    
    private let progressBar: UIProgressView = {
        let p = UIProgressView(progressViewStyle: .default)
        p.trackTintColor     = AppColor.UI.dashboardSecondaryBg
        p.layer.cornerRadius = 4
        p.clipsToBounds      = true
        return p
    }()
    
    private let remainingLabel: UILabel = {
        let l = UILabel()
        l.font          = .systemFont(ofSize: 11, weight: .bold)
        l.textColor     = AppColor.UI.textSecondary
        return l
    }()
    
    private let nextLevelLabel: UILabel = {
        let l = UILabel()
        l.font          = .systemFont(ofSize: 11, weight: .bold)
        l.textColor     = AppColor.UI.textSecondary
        l.textAlignment = .right
        return l
    }()
    
    private let tapGesture = UITapGestureRecognizer()
    private let disposeBag = DisposeBag()
    
    //MARK: - Init
    
    override init(frame: CGRect) {
        tapEvent = ControlEvent(events: tapGesture.rx.event.map { _ in })
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    //MARK: - Config
    
    override func configHierarchy() {
        addSubview(iconContainer)
        iconContainer.addSubview(iconView)
        addSubview(chevronView)
        addSubview(levelLabel)
        addSubview(totalLabel)
        addSubview(unitLabel)
        addSubview(progressBar)
        addSubview(remainingLabel)
        addSubview(nextLevelLabel)
    }
    override func configLayout() {
        iconContainer.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(24)
            make.size.equalTo(64)
        }
        
        iconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(28)
        }
        
        chevronView.snp.makeConstraints { make in
            make.centerY.equalTo(iconContainer)
            make.trailing.equalToSuperview().inset(24)
        }
        
        levelLabel.snp.makeConstraints {
            $0.top.equalTo(iconContainer.snp.bottom).offset(20)
            $0.leading.trailing.equalToSuperview().inset(24)
        }

        totalLabel.snp.makeConstraints {
            $0.top.equalTo(levelLabel.snp.bottom).offset(4)
            $0.leading.equalToSuperview().inset(24)
        }

        unitLabel.snp.makeConstraints {
            $0.leading.equalTo(totalLabel.snp.trailing).offset(6)
            $0.lastBaseline.equalTo(totalLabel)
        }

        progressBar.snp.makeConstraints {
            $0.top.equalTo(totalLabel.snp.bottom).offset(20)
            $0.leading.trailing.equalToSuperview().inset(24)
            $0.height.equalTo(8)
        }

        remainingLabel.snp.makeConstraints {
            $0.top.equalTo(progressBar.snp.bottom).offset(8)
            $0.leading.equalToSuperview().inset(24)
            $0.bottom.equalToSuperview().inset(24)
        }

        nextLevelLabel.snp.makeConstraints {
            $0.centerY.equalTo(remainingLabel)
            $0.trailing.equalToSuperview().inset(24)
        }
    }
    override func configView() {
        backgroundColor    = .white
        layer.cornerRadius = 24
        
        addGestureRecognizer(tapGesture)
        tapGesture.rx.event
            .subscribe(onNext: { [weak self] _ in
                guard let self else { return }
                UIView.animate(withDuration: 0.1, animations: {
                    self.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
                }) { _ in
                    UIView.animate(withDuration: 0.1) {
                        self.transform = .identity
                    }
                }
            })
            .disposed(by: disposeBag)
    }
    
    func configure(level: UserRunningLevel,
                   totalDistance: Double,
                   progress: Double,
                   remainingDistance: Double) {
        iconView.image     = UIImage(systemName: level.iconName)?
            .withConfiguration(UIImage.SymbolConfiguration(
                pointSize: 26,
                weight: .bold))
        iconView.tintColor = level.gradeColor
        
        levelLabel.text      = level.displayName
        levelLabel.textColor = level.gradeColor
        
        totalLabel.text = String(format: "%.1f", totalDistance)
        unitLabel.text  = "KM"
        
        progressBar.progress          = Float(progress)
        progressBar.progressTintColor = level.gradeColor
        
        if let next = level.nextThreshold {
            remainingLabel.text = String(format: "다음 등급까지 %.1fkm", remainingDistance)
            nextLevelLabel.text = "→ \(Int(next))km"
            remainingLabel.isHidden = false
            nextLevelLabel.isHidden = false
        } else {
            remainingLabel.text = "최고 등급 달성!"
            nextLevelLabel.isHidden = true
        }
    }
}
