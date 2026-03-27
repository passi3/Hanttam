//
//  HTReusableViewProtocol.swift
//  Hanttam
//
//  Created by passi on 3/27/26.
//

import UIKit

protocol HTReusableViewProtocol {
    
    static var identifier: String { get }
    
}

extension UITableViewCell: HTReusableViewProtocol {
    
    static var identifier: String {
        return String(describing: self)
    }
}

extension UICollectionViewCell: HTReusableViewProtocol {
    
    static var identifier: String {
        return String(describing: self)
    }
}
