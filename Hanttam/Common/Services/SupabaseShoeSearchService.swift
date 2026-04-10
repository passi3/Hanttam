//
//  SupabaseShoeSearchService.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import Foundation
import Supabase

protocol ShoeSearchServicing: AnyObject {
    func fetchInitialShoes(limit: Int, brand: String?, completion: @escaping (Result<[ShoeSearchResult], Error>) -> Void)
    func searchShoes(keyword: String, brand: String?, completion: @escaping (Result<[ShoeSearchResult], Error>) -> Void)
}

protocol BrandServicing: AnyObject {
    func fetchBrands(completion: @escaping (Result<[BrandSummary], Error>) -> Void)
}

protocol ShoeCatalogVariantServicing: AnyObject {
    func fetchVariants(
        brandName: String,
        modelName: String,
        completion: @escaping (Result<[ShoeCatalogItem], Error>) -> Void
    )
}

final class SupabaseShoeSearchService: ShoeSearchServicing, BrandServicing, ShoeCatalogVariantServicing {
    private enum Query {
        static let tableName = "shoe_models_view"
        static let rpcName = "search_shoes"
        static let selectColumns = "brand_id, brand_name, model_name, thumbnail_url, variants, variant_count"
        static let brandColumn = "brand_name"
        static let brandsTableName = "brands"
        static let brandSelectColumns = "id, name, slug, logo_url, sort_order"
    }

    private enum Diagnostics {
        static func log(_ message: @autoclosure () -> String) {
#if DEBUG
            print("[GearSearch] \(message())")
#endif
        }
    }

    func fetchInitialShoes(limit: Int, brand: String?, completion: @escaping (Result<[ShoeSearchResult], Error>) -> Void) {
        Task {
            do {
                Diagnostics.log("Initial fetch source=\(Query.tableName) limit=\(limit) brand=\(brand ?? "-")")
                var query = supabase
                    .from(Query.tableName)
                    .select(Query.selectColumns)
                if let brand, !brand.isEmpty {
                    query = query.ilike(Query.brandColumn, pattern: brand)
                }
                let response = try await query
                    .order("brand_name", ascending: true)
                    .order("model_name", ascending: true)
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

    func searchShoes(keyword: String, brand: String?, completion: @escaping (Result<[ShoeSearchResult], Error>) -> Void) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            fetchInitialShoes(limit: 20, brand: brand, completion: completion)
            return
        }

        Task {
            do {
                Diagnostics.log("Search source=\(Query.rpcName) keyword=\(trimmed) brand=\(brand ?? "-")")
                let response = try await supabase
                    .rpc(Query.rpcName, params: ["keyword": trimmed])
                    .execute()
                let decodedItems = try decodeItems(from: response.data)
                let items: [ShoeSearchResult]
                if let brand, !brand.isEmpty {
                    items = decodedItems.filter { $0.brandName.compare(brand, options: .caseInsensitive) == .orderedSame }
                } else {
                    items = decodedItems
                }
                DispatchQueue.main.async { completion(.success(items)) }
            } catch {
                Diagnostics.log("Search failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func fetchBrands(completion: @escaping (Result<[BrandSummary], Error>) -> Void) {
        Task {
            do {
                Diagnostics.log("Fetch brands source=\(Query.brandsTableName)")
                let response = try await supabase
                    .from(Query.brandsTableName)
                    .select(Query.brandSelectColumns)
                    .order("sort_order", ascending: true)
                    .order("name", ascending: true)
                    .execute()
                let decoder = JSONDecoder()
                let brands = try decoder.decode([BrandSummary].self, from: response.data)
                DispatchQueue.main.async { completion(.success(brands)) }
            } catch {
                Diagnostics.log("Fetch brands failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func fetchVariants(
        brandName: String,
        modelName: String,
        completion: @escaping (Result<[ShoeCatalogItem], Error>) -> Void
    ) {
        Task {
            do {
                Diagnostics.log("Fetch variants brand=\(brandName) model=\(modelName)")
                let response = try await supabase
                    .from(Query.tableName)
                    .select(Query.selectColumns)
                    .eq("brand_name", value: brandName)
                    .eq("model_name", value: modelName)
                    .limit(1)
                    .execute()
                let results = try decodeItems(from: response.data)
                let items = results.first?.catalogItems ?? []
                DispatchQueue.main.async { completion(.success(items)) }
            } catch {
                Diagnostics.log("Fetch variants failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func decodeItems(from data: Data) throws -> [ShoeSearchResult] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ShoeSearchResult].self, from: data)
    }
}
