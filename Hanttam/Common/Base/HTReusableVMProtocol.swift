//
//  HTReusableVMProtocol.swift
//  Hanttam
//
//  Created by passi on 3/27/26.
//

import Foundation
import RxSwift
import RxCocoa

protocol HTReusableVMProtocol {
    associatedtype Input
    associatedtype Output
    
    func transform(input: Input) -> Output
}
