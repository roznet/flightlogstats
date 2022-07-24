//
//  FlightListDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/07/2022.
//

import UIKit
import OSLog
import RZUtils
import RZUtilsSwift

class FlightListDataSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, TableCollectionDelegate   {

    enum CellHolder {
        case attributedString(NSAttributedString)
        case numberWithUnit(GCNumberWithUnit)
        
        init(string : String, attributes: [NSAttributedString.Key:Any] ) {
            self = .attributedString(NSAttributedString(string: string, attributes: attributes))
        }
    }
    
    var logList : FlightLogFileList? = nil
    var logFileOrganizer = FlightLogOrganizer.shared
    
    let displayContext : DisplayContext
    
    private var cellHolders : [CellHolder] = []
    private var geometries : [RZNumberWithUnitGeometry] = []
    
    var frozenColumns : Int = 1
    var frozenRows : Int = 1
    
    //               Total    Left   Right
    //    Start
    //    End
    //    Remaining
    
    init(displayContext : DisplayContext = DisplayContext()){
        self.logList = self.logFileOrganizer.nonEmptyLogFileList
        self.displayContext = displayContext
    }
    
    //MARK: - delegate
        
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    func prepare() {
        
        self.cellHolders  = []
        self.geometries = []
        
        
        for title in [ "Date", "From", "To", "Start", "Takeoff", "Landing", "End", "Flight",  ] {
            self.cellHolders.append(CellHolder(string: title, attributes: self.titleAttributes))
            let geometry = RZNumberWithUnitGeometry()
            geometry.defaultUnitAttribute = self.cellAttributes
            geometry.defaultNumberAttribute = self.cellAttributes
            geometry.numberAlignment = .right
            geometry.unitAlignment = .left
            geometry.alignment = .center
            self.geometries.append(geometry)
        }
    }
    
    func cellHolder(at indexPath : IndexPath) -> CellHolder {
        let index = indexPath.section * 5 + indexPath.item
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
        return 4
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 5
    }
    
    func setBackground(for tableCell: UICollectionViewCell, itemAt indexPath : IndexPath) {
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
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch self.cellHolder(at: indexPath) {
        case .attributedString(let attributedString):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TableCollectionViewCell", for: indexPath)
            if let tableCell = cell as? TableCollectionViewCell {
                tableCell.label.attributedText = attributedString
            }
            self.setBackground(for: cell, itemAt: indexPath)
            
            return cell
        case .numberWithUnit(let nu):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "NumberWithUnitCollectionViewCell", for: indexPath)
            if let nuCell = cell as? RZNumberWithUnitCollectionViewCell {
                nuCell.numberWithUnitView.numberWithUnit = nu
                nuCell.numberWithUnitView.geometry = self.geometries[indexPath.item]
            }
            self.setBackground(for: cell, itemAt: indexPath)
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.app.info("Selected \(indexPath)")
    }


}
