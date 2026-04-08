//
//  SupabaseShoeSearchService.swift
//  Hanttam
//
//  Created by Codex on 4/8/26.
//

import Foundation
import Supabase

protocol ShoeSearchServicing: AnyObject {
    func fetchInitialShoes(limit: Int, completion: @escaping (Result<[ShoeCatalogItem], Error>) -> Void)
    func searchShoes(keyword: String, completion: @escaping (Result<[ShoeCatalogItem], Error>) -> Void)
}

final class SupabaseShoeSearchService: ShoeSearchServicing {
    private enum Query {
        static let tableName = "shoes"
        static let selectColumns = "id, model_name, sku, colors, image_url, created_at, brand_name"
        static let searchColumn = "model_name"
    }

    private enum Diagnostics {
        static func log(_ message: @autoclosure () -> String) {
#if DEBUG
            print("[GearSearch] \(message())")
#endif
        }
    }

    func fetchInitialShoes(limit: Int, completion: @escaping (Result<[ShoeCatalogItem], Error>) -> Void) {
        Task {
            do {
                Diagnostics.log("Initial fetch source=\(Query.tableName) limit=\(limit)")
                let response = try await supabase
                    .from(Query.tableName)
                    .select(Query.selectColumns)
                    .order("created_at", ascending: false)
                    .limit(limit)
                    .execute()
                let items = try decodeItems(from: response.data)
                DispatchQueue.main.async { completion(.success(items)) }
            } catch {
                Diagnostics.log("Initial fetch failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func searchShoes(keyword: String, completion: @escaping (Result<[ShoeCatalogItem], Error>) -> Void) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fetchInitialShoes(limit: 20, completion: completion)
            return
        }

        Task {
            do {
                Diagnostics.log("Search source=\(Query.tableName).\(Query.searchColumn) keyword=\(trimmed)")
                let response = try await supabase
                    .from(Query.tableName)
                    .select(Query.selectColumns)
                    .ilike(Query.searchColumn, pattern: "%\(trimmed)%")
                    .order("created_at", ascending: false)
                    .execute()
                let items = try decodeItems(from: response.data)
                DispatchQueue.main.async { completion(.success(items)) }
            } catch {
                Diagnostics.log("Search failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func decodeItems(from data: Data) throws -> [ShoeCatalogItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ShoeCatalogItem].self, from: data)
    }
}
