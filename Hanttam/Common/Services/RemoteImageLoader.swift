//
//  RemoteImageLoader.swift
//  Hanttam
//
//  Created by passi on 4/8/26.
//

import UIKit

final class RemoteImageLoader {
    static let shared = RemoteImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
    }

    @discardableResult
    func loadImage(
        from urlString: String?,
        completion: @escaping (UIImage?) -> Void
    ) -> URLSessionDataTask? {
        guard
            let urlString,
            let url = URL(string: urlString)
        else {
            DispatchQueue.main.async { completion(nil) }
            return nil
        }

        if let cachedImage = cache.object(forKey: url as NSURL) {
            DispatchQueue.main.async { completion(cachedImage) }
            return nil
        }

        let task = session.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(UIImage.init(data:))
            if let image {
                self?.cache.setObject(image, forKey: url as NSURL)
            }
            DispatchQueue.main.async { completion(image) }
        }
        task.resume()
        return task
    }
}
