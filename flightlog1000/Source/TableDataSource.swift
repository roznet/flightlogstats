//
//  TableDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 29/07/2022.
//

import Foundation

import UIKit
import OSLog
import RZUtils
import RZUtilsSwift

class TableDataSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, TableCollectionDelegate   {

    enum CellHolder {
        case attributedString(NSAttributedString)
        case numberWithUnit(GCNumberWithUnit)
        
        init(string : String, attributes: [NSAttributedString.Key:Any] ) {
            self = .attributedString(NSAttributedString(string: string, attributes: attributes))
        }
    }
    
    var cellHolders : [CellHolder] = []
    var geometries : [RZNumberWithUnitGeometry] = []
    
    var frozenColumns : Int
    var frozenRows : Int
    
    var columnsCount : Int
    var rowsCount : Int
    
    //               Total    Left   Right
    //    Start
    //    End
    //    Remaining

    init(rows : Int, columns : Int, frozenColumns : Int, frozenRows : Int) {
        self.rowsCount = rows
        self.columnsCount = columns
        self.frozenRows = frozenRows
        self.frozenColumns = frozenColumns
    }
    
    //MARK: - delegate
    
    // To override
    func attribute(at indexPath : IndexPath) -> [NSAttributedString.Key:Any] {
        if indexPath.section < self.frozenRows || indexPath.item < self.frozenColumns{
            return [.font:UIFont.boldSystemFont(ofSize: 14.0)]
        }else{
            return [.font:UIFont.systemFont(ofSize: 14.0)]
        }
    }
    
    func setBackgroundColor(for tableCell: UICollectionViewCell, itemAt indexPath : IndexPath) {
        if indexPath.section < self.frozenRows || indexPath.item < self.frozenColumns{
            tableCell.backgroundColor = UIColor.systemCyan
        }else{
            if indexPath.section % 2 == 0{
                tableCell.backgroundColor = UIColor.systemBackground
            }else{
                tableCell.backgroundColor = UIColor.systemGroupedBackground
            }
        }
    }

    func prepare() {
        self.cellHolders  = []
        self.geometries = []
    }

    //MARK: - common logic
    private func cellHolder(at indexPath : IndexPath) -> CellHolder {
        let index = indexPath.section * self.columnsCount + indexPath.item
        return self.cellHolders[index]
    }
    
    func size(at indexPath: IndexPath) -> CGSize {
        switch self.cellHolder(at: indexPath) {
        case .attributedString(let attributedString):
            return attributedString.size()
        case .numberWithUnit:
            return self.geometries[indexPath.item].totalSize
        }
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return self.rowsCount
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.columnsCount
    }
    
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let holder = self.cellHolder(at: indexPath)
        switch holder {
        case .attributedString(let attributedString):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TableCollectionViewCell", for: indexPath)
            if let tableCell = cell as? TableCollectionViewCell {
                tableCell.label.attributedText = attributedString
            }
            self.setBackgroundColor(for: cell, itemAt: indexPath)
            
            return cell
        case .numberWithUnit(let nu):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "NumberWithUnitCollectionViewCell", for: indexPath)
            if let nuCell = cell as? RZNumberWithUnitCollectionViewCell {
                nuCell.numberWithUnitView.numberWithUnit = nu
                nuCell.numberWithUnitView.geometry = self.geometries[indexPath.item]
            }
            self.setBackgroundColor(for: cell, itemAt: indexPath)
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.app.info("Selected \(indexPath)")
    }


}
