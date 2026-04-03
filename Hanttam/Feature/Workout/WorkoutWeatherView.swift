//
//  WorkoutWeatherView.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import SwiftUI

struct WorkoutWeatherView: View {

    @ObservedObject private var weather = WeatherKitManager.shared
    @State private var weatherPage = 0

    private let pageCount = 2

    var body: some View {
        VStack(spacing: 4) {
            // Page indicator
            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == weatherPage ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: i == weatherPage ? 20 : 6, height: 6)
                }
            }
            .animation(.spring(duration: 0.3), value: weatherPage)

            TabView(selection: $weatherPage) {
                temperatureCard
                    .tag(0)
                sunCard
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 104)
        }
    }

    // MARK: - Temperature Card

    private var temperatureCard: some View {
        HStack(spacing: 10) {
            Image(systemName: weather.conditionSymbol)
                .font(AppFont.headlineLG)
                .symbolRenderingMode(.multicolor)

            VStack(alignment: .leading, spacing: 2) {
                if let temp = weather.temperature {
                    Text(String(format: "%.0f°", temp))
                        .font(AppFont.roundedHeadline)
                        .foregroundStyle(AppColor.textInverse)
                } else {
                    Text("--°")
                        .font(AppFont.roundedHeadline)
                        .foregroundStyle(AppColor.textInverseMuted)
                }
                if !weather.conditionDescription.isEmpty {
                    Text(weather.conditionDescription)
                        .font(AppFont.labelLG.weight(.regular))
                        .foregroundStyle(AppColor.textInverseSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            weatherAttribution
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColor.weatherCardBackground, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 40)
    }

    // MARK: - Sunrise / Sunset Card

    private var sunCard: some View {
        let isSunrise = !weather.isDaytime || weather.sunsetDate == nil
        let icon = isSunrise ? "sunrise.fill" : "sunset.fill"
        let label = isSunrise ? "일출" : "일몰"
        let time = isSunrise ? weather.sunriseDate : weather.sunsetDate

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppFont.headlineLG)
                .symbolRenderingMode(.multicolor)

            VStack(alignment: .leading, spacing: 2) {
                if let time {
                    Text(time.formatted(.dateTime.hour().minute()))
                        .font(AppFont.roundedHeadline)
                        .foregroundStyle(AppColor.textInverse)
                } else {
                    Text("--:--")
                        .font(AppFont.roundedHeadline)
                        .foregroundStyle(AppColor.textInverseMuted)
                }
                Text(label)
                    .font(AppFont.labelLG.weight(.regular))
                    .foregroundStyle(AppColor.textInverseSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            weatherAttribution
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColor.weatherCardBackground, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 40)
    }

    // MARK: - Attribution (Apple Weather 상표)

    private var weatherAttribution: some View {
        Group {
            if let logoURL = weather.attributionLogoURL,
               let linkURL = weather.attributionLinkURL {
                Link(destination: linkURL) {
                    AsyncImage(url: logoURL) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Text(" Weather")
                            .font(AppFont.captionSM)
                            .foregroundStyle(AppColor.textInverseTertiary)
                    }
                    .frame(height: 12)
                }
            } else {
                Text(" Weather")
                    .font(AppFont.captionSM)
                    .foregroundStyle(AppColor.textInverseTertiary)
            }
        }
        .padding(.leading, 2)
    }
}

#Preview {
    WorkoutWeatherView()
}
