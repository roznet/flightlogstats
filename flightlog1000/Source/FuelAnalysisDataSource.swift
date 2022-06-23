//
//  FuelAnalysisDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import UIKit
import OSLog
import RZUtils

class FuelAnalysisDataSource: NSObject, UICollectionViewDataSource, UICollectionViewDelegate, TableCollectionDelegate {
    let flightSummary : FlightSummary
    let displayContext : DisplayContext
    
    
    var fuelTarget : FuelQuantity
    var fuelAdded : FuelQuantity
    
    var fuelTargetUnit : GCUnit
    var fuelAddedUnit : GCUnit
    
    private var attributedCells : [NSAttributedString] = []
    
    var frozenColumns : Int = 1
    var frozenRows : Int = 1
    
    private(set) var sections : Int = 0
    private(set) var items : Int = 4
    
    init(flightSummary : FlightSummary, displayContext : DisplayContext = DisplayContext()){
        self.flightSummary = flightSummary
        self.displayContext = displayContext
        
        self.fuelTargetUnit = GCUnit.usgallon()
        self.fuelAddedUnit = GCUnit.liter()

        fuelTarget = FuelQuantity(total: 92.0, unit:self.fuelTargetUnit)
        
        self.fuelAdded = FuelQuantity(total: 10.0, unit: self.fuelAddedUnit)
        
    }
    
    //MARK: - delegate
    
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    func addSeparator() {
        for _ in 0..<4 {
            self.attributedCells.append(NSAttributedString(string: "", attributes: self.titleAttributes))
        }
        self.sections += 1
    }
    
    func addLine(name : String, fuel : FuelQuantity, unit : GCUnit) {
        self.attributedCells.append(NSAttributedString(string: name, attributes: self.titleAttributes))
        self.attributedCells.append(NSAttributedString(string: self.displayContext.formatValue(numberWithUnit: fuel.totalWithUnit, converted: unit),
                                                       attributes: self.cellAttributes))
        self.attributedCells.append(NSAttributedString(string: self.displayContext.formatValue(numberWithUnit: fuel.leftWithUnit, converted: unit),
                                                       attributes: self.cellAttributes))
        self.attributedCells.append(NSAttributedString(string: self.displayContext.formatValue(numberWithUnit: fuel.rightWithUnit, converted: unit),
                                                       attributes: self.cellAttributes))
        self.sections += 1
    }
    
    func prepare() {
        
        self.attributedCells  = []
        
        for title in [ "Fuel", "Total", "Left", "Right" ] {
            self.attributedCells.append(NSAttributedString(string: title, attributes: self.titleAttributes))
        }
        self.sections = 1
        
        self.addSeparator()
        
        for (name,fuel,unit) in [
            ("Current", self.flightSummary.fuelEnd, GCUnit.usgallon()),
            ("Target", self.fuelTarget, GCUnit.usgallon()),
            ("Added", self.fuelAdded, GCUnit.liter()),
        ] {
            self.addLine(name: name, fuel: fuel, unit: unit)
        }
        
        self.addSeparator()
        
        for (name,fuel,unit) in [
            ("Total", self.flightSummary.fuelEnd+self.fuelAdded, GCUnit.usgallon()),
            ("Added", self.fuelAdded, GCUnit.avgasKilogram()),
        ] {
            self.addLine(name: name, fuel: fuel, unit: unit)
        }

    }
    
    func attributedString(at indexPath : IndexPath) -> NSAttributedString {
        let index = indexPath.section * 4 + indexPath.item
        return self.attributedCells[index]
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return self.sections
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.items
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "TableCollectionViewCell", for: indexPath)
        if let tableCell = cell as? TableCollectionViewCell {
            tableCell.label.attributedText = self.attributedString(at: indexPath)
            
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
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.app.info("Selected \(indexPath)")
    }
}

