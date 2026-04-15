//
//  GearDetailHeaderView.swift
//  Hanttam
//

import UIKit
import SnapKit

final class GearDetailHeaderView: HTView {
    private let distanceValueLabel = UILabel()
    private let distanceUnitLabel  = UILabel()
    private let shoeImageView      = UIImageView()
    private let progressLabel      = UILabel()
    private let progressView       = UIProgressView(progressViewStyle: .default)

    private var imageTask: URLSessionDataTask?
    private var currentImageURL: String?
    private let shoe: RegisteredShoe

    init(shoe: RegisteredShoe) {
        self.shoe = shoe
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func configHierarchy() {
        [distanceValueLabel, distanceUnitLabel, shoeImageView, progressLabel, progressView].forEach { addSubview($0) }
    }

    override func configLayout() {
        distanceValueLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(28)
            make.centerX.equalToSuperview()
        }
        distanceUnitLabel.snp.makeConstraints { make in
            make.top.equalTo(distanceValueLabel.snp.bottom).offset(-18)
            make.centerX.equalToSuperview()
        }
        shoeImageView.snp.makeConstraints { make in
            make.top.equalTo(distanceUnitLabel.snp.top).offset(-52)
            make.leading.trailing.equalToSuperview().inset(20)
            make.height.equalTo(220)
        }
        progressLabel.snp.makeConstraints { make in
            make.top.equalTo(shoeImageView.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        progressView.snp.makeConstraints { make in
            make.top.equalTo(progressLabel.snp.bottom).offset(12)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(24)
            make.height.equalTo(8)
        }
    }

    override func configView() {
        backgroundColor = AppColor.UI.cardBackground
        layer.cornerRadius = 28
        layer.borderWidth = 1
        layer.borderColor = AppColor.UI.border.cgColor

        distanceValueLabel.font = .systemFont(ofSize: 70, weight: .black)
        distanceValueLabel.textColor = .black
        distanceValueLabel.textAlignment = .center

        distanceUnitLabel.font = .systemFont(ofSize: 70, weight: .black)
        distanceUnitLabel.textColor = .black
        distanceUnitLabel.text = "KM"
        distanceUnitLabel.textAlignment = .center

        shoeImageView.contentMode = .scaleAspectFit
        shoeImageView.image = UIImage(systemName: "shoeprints.fill")
        shoeImageView.tintColor = AppColor.UI.textSecondary

        progressLabel.font = AppFont.UI.headlineSM
        progressLabel.textColor = AppColor.UI.textPrimary
        progressLabel.textAlignment = .center
        progressLabel.numberOfLines = 0

        progressView.trackTintColor = AppColor.UI.border
        progressView.progressTintColor = RunningLevelManager.shared.accentUIColor
        progressView.layer.cornerRadius = 4
        progressView.clipsToBounds = true
    }

    func configure(with shoe: RegisteredShoe, stats: ShoeAggregateStats) {
        distanceValueLabel.text = formattedDistanceText(for: stats.totalDistance)

        if stats.overDistance > 0 {
            progressLabel.text = "목표 \(AppFormatter.distance1f(shoe.targetDistanceMeters)) 초과 · +\(AppFormatter.distance1f(stats.overDistance))"
        } else {
            let remaining = max(shoe.targetDistanceMeters - stats.totalDistance, 0)
            progressLabel.text = "목표 달성까지 \(AppFormatter.distance1f(remaining))"
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
    }

    private func formattedDistanceText(for distanceMeters: Double) -> String {
        let km = distanceMeters / 1000.0
        let rounded = (km * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.05 { return "\(Int(rounded.rounded()))" }
        return String(format: "%.1f", rounded)
    }
}
