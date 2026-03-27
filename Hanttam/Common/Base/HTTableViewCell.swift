//
//  HTTableViewCell.swift
//  Hanttam
//
//  Created by passi on 3/27/26.
//

import UIKit

class HTTableViewCell: UITableViewCell {

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
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
