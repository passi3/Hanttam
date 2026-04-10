//
//  GearLocalStore.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import Foundation

protocol GearLocalStoring: AnyObject {
    func fetchRegisteredShoes() -> [RegisteredShoe]
    func saveRegisteredShoe(_ shoe: RegisteredShoe)
    func updateRegisteredShoe(_ shoe: RegisteredShoe)
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
    private let queue = DispatchQueue(label: "com.hanttam.gear.local-store", qos: .userInitiated)

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func fetchRegisteredShoes() -> [RegisteredShoe] {
        queue.sync {
            load([RegisteredShoe].self, from: registeredShoesURL) ?? []
        }
    }

    func saveRegisteredShoe(_ shoe: RegisteredShoe) {
        queue.sync {
            var shoes = load([RegisteredShoe].self, from: registeredShoesURL) ?? []
            shoes.append(shoe)
            save(shoes, to: registeredShoesURL)
        }
        notifyChange()
    }

    func updateRegisteredShoe(_ shoe: RegisteredShoe) {
        queue.sync {
            var shoes = load([RegisteredShoe].self, from: registeredShoesURL) ?? []
            guard let index = shoes.firstIndex(where: { $0.id == shoe.id }) else { return }
            shoes[index] = shoe
            save(shoes, to: registeredShoesURL)
        }
        notifyChange()
    }

    func fetchSessionLinks() -> [ShoeSessionLink] {
        queue.sync {
            load([ShoeSessionLink].self, from: sessionLinksURL) ?? []
        }
    }

    func upsertSessionLink(_ link: ShoeSessionLink) {
        queue.sync {
            var links = load([ShoeSessionLink].self, from: sessionLinksURL) ?? []
            links.removeAll { $0.sessionKind == link.sessionKind && $0.sessionIdentifier == link.sessionIdentifier }
            links.append(link)
            save(links, to: sessionLinksURL)
        }
        notifyChange()
    }

    func removeSessionLink(sessionIdentifier: String, kind: GearSessionKind) {
        queue.sync {
            var links = load([ShoeSessionLink].self, from: sessionLinksURL) ?? []
            links.removeAll { $0.sessionKind == kind && $0.sessionIdentifier == sessionIdentifier }
            save(links, to: sessionLinksURL)
        }
        notifyChange()
    }

    func linkedShoe(
        for sessionIdentifier: String,
        kind: GearSessionKind
    ) -> RegisteredShoe? {
        let links = fetchSessionLinks()
        guard let link = links.first(where: { $0.sessionIdentifier == sessionIdentifier && $0.sessionKind == kind }) else {
            return nil
        }
        return fetchRegisteredShoes().first(where: { $0.id == link.shoeID })
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

    private func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func notifyChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }
}
