//
//  GearLocalStore.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import Foundation
import RealmSwift

protocol GearLocalStoring: AnyObject {
    func fetchRegisteredShoes() -> [RegisteredShoe]
    func saveRegisteredShoe(_ shoe: RegisteredShoe)
    func updateRegisteredShoe(_ shoe: RegisteredShoe)
    func deleteRegisteredShoe(id: UUID)
    func fetchSessionLinks() -> [ShoeSessionLink]
    func upsertSessionLink(_ link: ShoeSessionLink)
    func removeSessionLink(sessionIdentifier: String, kind: GearSessionKind)
    func linkedShoe(
        for sessionIdentifier: String,
        kind: GearSessionKind
    ) -> RegisteredShoe?
}

final class GearLocalStore: GearLocalStoring {
    static let shared = GearLocalStore()
    static let didChangeNotification = Notification.Name("GearLocalStore.didChange")

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let migrationQueue = DispatchQueue(label: "com.hanttam.gear.realm-migration", qos: .userInitiated)

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        migrateJSONIfNeeded()
        print(">>>>>>>>>>>>>>", Realm.Configuration.defaultConfiguration.fileURL!)
    }

    func fetchRegisteredShoes() -> [RegisteredShoe] {
        withRealm { realm in
            realm.objects(RegisteredShoeObject.self)
                .sorted(byKeyPath: "registeredAt", ascending: true)
                .map(\.asDomainModel)
        } ?? []
    }

    func saveRegisteredShoe(_ shoe: RegisteredShoe) {
        write { realm in
            realm.add(RegisteredShoeObject(shoe: shoe), update: .modified)
        }
        notifyChange()
    }

    func updateRegisteredShoe(_ shoe: RegisteredShoe) {
        write { realm in
            realm.add(RegisteredShoeObject(shoe: shoe), update: .modified)
        }
        notifyChange()
    }

    func deleteRegisteredShoe(id: UUID) {
        let shoeIDString = id.uuidString
        write { realm in
            if let shoeObject = realm.object(ofType: RegisteredShoeObject.self, forPrimaryKey: shoeIDString) {
                realm.delete(shoeObject)
            }

            let linkedSessions = realm.objects(ShoeSessionLinkObject.self)
                .where { $0.shoeIDString == shoeIDString }
            realm.delete(linkedSessions)
        }
        notifyChange()
    }

    func fetchSessionLinks() -> [ShoeSessionLink] {
        withRealm { realm in
            realm.objects(ShoeSessionLinkObject.self)
                .sorted(byKeyPath: "workoutStartDate", ascending: true)
                .map(\.asDomainModel)
        } ?? []
    }

    func upsertSessionLink(_ link: ShoeSessionLink) {
        write { realm in
            realm.add(ShoeSessionLinkObject(link: link), update: .modified)
        }
        notifyChange()
    }

    func removeSessionLink(sessionIdentifier: String, kind: GearSessionKind) {
        write { realm in
            let objects = realm.objects(ShoeSessionLinkObject.self)
                .where {
                    $0.sessionIdentifier == sessionIdentifier &&
                    $0.sessionKindRaw == kind.rawValue
                }
            realm.delete(objects)
        }
        notifyChange()
    }

    func linkedShoe(
        for sessionIdentifier: String,
        kind: GearSessionKind
    ) -> RegisteredShoe? {
        withRealm { realm in
            guard let link = realm.objects(ShoeSessionLinkObject.self)
                .where({
                    $0.sessionIdentifier == sessionIdentifier &&
                    $0.sessionKindRaw == kind.rawValue
                })
                .first
            else {
                return nil
            }
            return realm.object(ofType: RegisteredShoeObject.self, forPrimaryKey: link.shoeIDString)?.asDomainModel
        } ?? nil
    }

    private func migrateJSONIfNeeded() {
        migrationQueue.sync {
            guard let realm = makeRealm() else { return }
            let hasRealmData =
                !realm.objects(RegisteredShoeObject.self).isEmpty ||
                !realm.objects(ShoeSessionLinkObject.self).isEmpty
            let hasLegacyFiles =
                fileManager.fileExists(atPath: registeredShoesURL.path) ||
                fileManager.fileExists(atPath: sessionLinksURL.path)

            guard !hasRealmData, hasLegacyFiles else { return }

            let shoes = load([RegisteredShoe].self, from: registeredShoesURL) ?? []
            let links = load([ShoeSessionLink].self, from: sessionLinksURL) ?? []

            guard !shoes.isEmpty || !links.isEmpty else { return }

            do {
                try realm.write {
                    shoes.forEach { realm.add(RegisteredShoeObject(shoe: $0), update: .modified) }
                    links.forEach { realm.add(ShoeSessionLinkObject(link: $0), update: .modified) }
                }
            } catch {
                assertionFailure("Failed to migrate gear JSON to Realm: \(error)")
            }
        }
    }

    private func withRealm<T>(_ block: (Realm) -> T) -> T? {
        guard let realm = makeRealm() else { return nil }
        return block(realm)
    }

    private func write(_ block: (Realm) -> Void) {
        guard let realm = makeRealm() else { return }
        do {
            try realm.write {
                block(realm)
            }
        } catch {
            assertionFailure("Realm write failed: \(error)")
        }
    }

    private func makeRealm() -> Realm? {
        do {
            return try Realm()
        } catch {
            assertionFailure("Failed to open Realm: \(error)")
            return nil
        }
    }

    private var baseDirectoryURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("HanttamGear", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private var registeredShoesURL: URL {
        baseDirectoryURL.appendingPathComponent("registered_shoes.json")
    }

    private var sessionLinksURL: URL {
        baseDirectoryURL.appendingPathComponent("session_links.json")
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}

@objc(RegisteredShoeObject)
final class RegisteredShoeObject: Object {
    @Persisted(primaryKey: true) var id: String
    @Persisted var catalogID: String = ""
    @Persisted var nickname: String?
    @Persisted var brandName: String = ""
    @Persisted var modelName: String = ""
    @Persisted var sku: String = ""
    @Persisted var colors = List<String>()
    @Persisted var imageURL: String?
    @Persisted var createdAt: Date?
    @Persisted var registeredAt: Date = Date()
    @Persisted var targetDistanceMeters: Double = 0
    @Persisted var initialDistanceMeters: Double = 0

    convenience init(shoe: RegisteredShoe) {
        self.init()
        id = shoe.id.uuidString
        catalogID = shoe.catalogID
        nickname = shoe.nickname
        brandName = shoe.brandName
        modelName = shoe.modelName
        sku = shoe.sku
        colors.removeAll()
        colors.append(objectsIn: shoe.colors)
        imageURL = shoe.imageURL
        createdAt = shoe.createdAt
        registeredAt = shoe.registeredAt
        targetDistanceMeters = shoe.targetDistanceMeters
        initialDistanceMeters = shoe.initialDistanceMeters
    }

    var asDomainModel: RegisteredShoe {
        RegisteredShoe(
            id: UUID(uuidString: id) ?? UUID(),
            catalogID: catalogID,
            nickname: nickname,
            brandName: brandName,
            modelName: modelName,
            sku: sku,
            colors: Array(colors),
            imageURL: imageURL,
            createdAt: createdAt,
            registeredAt: registeredAt,
            targetDistanceMeters: targetDistanceMeters,
            initialDistanceMeters: initialDistanceMeters
        )
    }
}

@objc(ShoeSessionLinkObject)
final class ShoeSessionLinkObject: Object {
    @Persisted(primaryKey: true) var id: String
    @Persisted var shoeIDString: String = ""
    @Persisted var sessionKindRaw: String = ""
    @Persisted var sessionIdentifier: String = ""
    @Persisted var workoutStartDate: Date = Date()
    @Persisted var workoutEndDate: Date = Date()

    convenience init(link: ShoeSessionLink) {
        self.init()
        id = link.id
        shoeIDString = link.shoeID.uuidString
        sessionKindRaw = link.sessionKind.rawValue
        sessionIdentifier = link.sessionIdentifier
        workoutStartDate = link.workoutStartDate
        workoutEndDate = link.workoutEndDate
    }

    var asDomainModel: ShoeSessionLink {
        ShoeSessionLink(
            shoeID: UUID(uuidString: shoeIDString) ?? UUID(),
            sessionKind: GearSessionKind(rawValue: sessionKindRaw) ?? .freeRun,
            sessionIdentifier: sessionIdentifier,
            workoutStartDate: workoutStartDate,
            workoutEndDate: workoutEndDate
        )
    }
}
