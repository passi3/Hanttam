//
//  WeatherKitManager.swift
//  Hanttam
//
//  Created by passi on 4/3/26.
//

import Foundation
import WeatherKit
import CoreLocation
import Combine

@MainActor
final class WeatherKitManager: ObservableObject {

    static let shared = WeatherKitManager()

    @Published var temperature         : Double?
    @Published var conditionSymbol     : String = "cloud.sun"
    @Published var conditionDescription: String = ""
    @Published var sunriseDate         : Date?
    @Published var sunsetDate          : Date?
    @Published var isDaytime           : Bool = true
    @Published var hasFetched          : Bool = false
    @Published var attributionLogoURL   : URL?
    @Published var attributionLinkURL   : URL?

    private let service = WeatherKit.WeatherService.shared
    private var lastFetchDate: Date?
    private init() {}

    func fetch(for location: CLLocation) async {
        // 5분 내 재요청 방지
        if let last = lastFetchDate, Date().timeIntervalSince(last) < 300 { return }

        do {
            let weather = try await service.weather(for: location)
            let current = weather.currentWeather
            temperature = current.temperature.value
            conditionSymbol = current.symbolName
            conditionDescription = current.condition.description
            isDaytime = current.isDaylight

            if let today = weather.dailyForecast.first {
                sunriseDate = today.sun.sunrise
                sunsetDate = today.sun.sunset
            }
            hasFetched = true
            lastFetchDate = Date()

            // Apple Weather 상표 정보
            let attribution = try await service.attribution
            attributionLogoURL = attribution.combinedMarkDarkURL
            attributionLinkURL = attribution.legalPageURL
        } catch {
            print("[WeatherService] fetch failed: \(error)")
        }
    }
}
