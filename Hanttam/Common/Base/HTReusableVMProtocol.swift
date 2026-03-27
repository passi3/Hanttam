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
    
    var disposeBag: DisposeBag { get set }
    
    func transform(input: Input) -> Output
}
