//
//  Table.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 11/05/2022.
//

import UIKit

protocol TableCollectionSizeDelegate : AnyObject {
    func size(at : IndexPath) -> CGSize
    
    func prepare()
}

class TableCollectionViewLayout: UICollectionViewLayout {

    weak var sizeDelegate : TableCollectionSizeDelegate? = nil
    
    override func prepare() {
        self.sizeDelegate?.prepare()
        
        
        
    }
    
}
