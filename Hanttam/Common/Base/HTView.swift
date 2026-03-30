//
//  HTView.swift
//  Hanttam
//
//  Created by passi on 3/30/26.
//

import UIKit

class HTView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
         configHierarchy()
         configLayout()
         configView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        fatalError("init(coder:) has not been implemented")
    }
    
    func configHierarchy() { }
    func configLayout() { }
    func configView() { }
}
