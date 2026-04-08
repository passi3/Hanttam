//
//  GearModels.swift
//  Hanttam
//
//  Created by Codex on 4/8/26.
//

import Foundation
internal import HealthKit

enum GearSessionKind: String, Codable, Hashable {
    case freeRun
    case interval

    var title: String {
        switch self {
        case .freeRun:
            return "자유런"
        case .interval:
            return "인터벌"
        }
    }
}

struct ShoeCatalogItem: Decodable, Hashable {
    let id: String
    let modelName: String
    let sku: String
    let colors: [String]
    let imageURL: String?
    let createdAt: Date?
    let brandName: String

    enum CodingKeys: String, CodingKey {
        case id
        case modelName = "model_name"
        case sku
        case colors
        case imageURL = "image_url"
        case createdAt = "created_at"
        case brandName = "brand_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try Self.decodeIdentifier(from: container, forKey: .id)
        modelName = try container.decode(String.self, forKey: .modelName)
        sku = try container.decodeIfPresent(String.self, forKey: .sku) ?? ""
        let rawColors = try container.decodeIfPresent(String.self, forKey: .colors) ?? ""
        colors = Self.parseColors(rawColors)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        brandName = try container.decodeIfPresent(String.self, forKey: .brandName) ?? ""
    }

    private static func decodeIdentifier(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            return stringValue
        }
        if let uuidValue = try? container.decode(UUID.self, forKey: key) {
            return uuidValue.uuidString
        }
        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: container.codingPath, debugDescription: "Unsupported identifier type")
        )
    }

    static func parseColors(_ rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let normalized = trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
            ? String(trimmed.dropFirst().dropLast())
            : trimmed

        let separator: Character = normalized.contains(",") ? "," : (normalized.contains("/") ? "/" : ",")
        return normalized
            .split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct RegisteredShoe: Codable, Hashable, Identifiable {
    let id: UUID
    let catalogID: String
    let brandName: String
    let modelName: String
    let sku: String
    let colors: [String]
    let imageURL: String?
    let createdAt: Date?
    let registeredAt: Date
    var targetDistanceMeters: Double

    init(
        id: UUID = UUID(),
        catalogID: String,
        brandName: String,
        modelName: String,
        sku: String,
        colors: [String],
        imageURL: String?,
        createdAt: Date?,
        registeredAt: Date = Date(),
        targetDistanceMeters: Double
    ) {
        self.id = id
        self.catalogID = catalogID
        self.brandName = brandName
        self.modelName = modelName
        self.sku = sku
        self.colors = colors
        self.imageURL = imageURL
        self.createdAt = createdAt
        self.registeredAt = registeredAt
        self.targetDistanceMeters = targetDistanceMeters
    }

    init(item: ShoeCatalogItem, targetDistanceMeters: Double) {
        self.init(
            catalogID: item.id,
            brandName: item.brandName,
            modelName: item.modelName,
            sku: item.sku,
            colors: item.colors,
            imageURL: item.imageURL,
            createdAt: item.createdAt,
            targetDistanceMeters: targetDistanceMeters
        )
    }
}

struct ShoeSessionLink: Codable, Hashable, Identifiable {
    let shoeID: UUID
    let sessionKind: GearSessionKind
    let sessionIdentifier: String
    let workoutStartDate: Date
    let workoutEndDate: Date

    var id: String {
        "\(shoeID.uuidString)-\(sessionKind.rawValue)-\(sessionIdentifier)"
    }
}

struct ShoeAggregateStats: Hashable {
    let totalDistance: Double
    let totalDuration: TimeInterval
    let averagePace: TimeInterval?
    let targetDistanceMeters: Double
    let overDistance: Double
    let progress: Double

    init(totalDistance: Double, totalDuration: TimeInterval, targetDistanceMeters: Double) {
        self.totalDistance = totalDistance
        self.totalDuration = totalDuration
        self.averagePace = totalDistance > 0 ? totalDuration / (totalDistance / 1000.0) : nil
        self.targetDistanceMeters = targetDistanceMeters
        self.overDistance = max(0, totalDistance - targetDistanceMeters)
        if targetDistanceMeters > 0 {
            self.progress = min(totalDistance / targetDistanceMeters, 1.0)
        } else {
            self.progress = 0
        }
    }
}

struct GearLinkedSessionItem: Hashable, Identifiable {
    let id: String
    let sessionKind: GearSessionKind
    let startedAt: Date
    let endedAt: Date
    let distance: Double
    let duration: TimeInterval
    let runningRecord: RunningRecord?
    let intervalRecord: IntervalRecord?

    var title: String { sessionKind.title }
}

enum GearSessionResolver {
    static func makeIdentifier(for record: RunningRecord) -> String {
        "\(record.date.timeIntervalSince1970)-\(record.endDate.timeIntervalSince1970)"
    }

    static func makeIdentifier(for intervalRecord: IntervalRecord) -> String {
        intervalRecord.id.uuidString
    }

    static func makeRunningRecord(from intervalRecord: IntervalRecord) -> RunningRecord? {
        guard let workout = intervalRecord.workout else { return nil }
        return RunningRecord(
            date: intervalRecord.date,
            endDate: workout.endDate,
            duration: intervalRecord.totalDuration,
            distance: intervalRecord.totalDistance,
            calories: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0,
            workout: workout,
            sourceName: workout.sourceRevision.source.name,
            deviceName: workout.device?.name ?? workout.device?.model,
            isIndoor: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
        )
    }

    static func linkedSessions(
        for shoe: RegisteredShoe,
        links: [ShoeSessionLink],
        runningRecords: [RunningRecord],
        intervalRecords: [IntervalRecord]
    ) -> [GearLinkedSessionItem] {
        let relevantLinks = links.filter { $0.shoeID == shoe.id }

        let freeRunLookup = Dictionary(uniqueKeysWithValues: runningRecords.map { (makeIdentifier(for: $0), $0) })
        let intervalLookup = Dictionary(uniqueKeysWithValues: intervalRecords.map { (makeIdentifier(for: $0), $0) })

        return relevantLinks.compactMap { link in
            switch link.sessionKind {
            case .freeRun:
                guard let record = freeRunLookup[link.sessionIdentifier] else { return nil }
                return GearLinkedSessionItem(
                    id: link.id,
                    sessionKind: .freeRun,
                    startedAt: record.date,
                    endedAt: record.endDate,
                    distance: record.distance,
                    duration: record.duration,
                    runningRecord: record,
                    intervalRecord: nil
                )
            case .interval:
                guard let intervalRecord = intervalLookup[link.sessionIdentifier] else { return nil }
                return GearLinkedSessionItem(
                    id: link.id,
                    sessionKind: .interval,
                    startedAt: link.workoutStartDate,
                    endedAt: link.workoutEndDate,
                    distance: intervalRecord.totalDistance,
                    duration: intervalRecord.totalDuration,
                    runningRecord: makeRunningRecord(from: intervalRecord),
                    intervalRecord: intervalRecord
                )
            }
        }
        .sorted { $0.startedAt > $1.startedAt }
    }
}

enum GearFormatters {
    static func duration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func pace(_ secondsPerKilometer: TimeInterval?) -> String {
        guard let secondsPerKilometer, secondsPerKilometer.isFinite else { return "-" }
        let totalSeconds = max(Int(secondsPerKilometer.rounded()), 0)
        return String(format: "%d:%02d /km", totalSeconds / 60, totalSeconds % 60)
    }
}

extension RunningRecord {
    var gearSessionIdentifier: String {
        GearSessionResolver.makeIdentifier(for: self)
    }
}

extension IntervalRecord {
    var gearSessionIdentifier: String {
        GearSessionResolver.makeIdentifier(for: self)
    }
}
