//
//  HTCollectionViewCell.swift
//  Hanttam
//
//  Created by passi on 3/27/26.
//

import UIKit

class HTCollectionViewCell: UICollectionViewCell {
 
    override init(frame: CGRect) {
        super.init(frame: frame)
        configHierarchy()
        configLayout()
        configView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func configHierarchy() { }
    func configLayout() { }
    func configView() { }
}
