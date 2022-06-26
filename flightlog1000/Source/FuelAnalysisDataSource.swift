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
    typealias Endurance = Aircraft.Endurance
    
    let flightSummary : FlightSummary
    let displayContext : DisplayContext
    
    var aircraft : Aircraft
    var fuelAnalysis : FuelAnalysis
        
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

        self.aircraft = Aircraft(fuelMax: FuelQuantity(total: 92.0, unit:GCUnit.usgallon()),
                                 fuelTab: FuelQuantity(total: 60.0, unit:GCUnit.usgallon()),
                                 gph: 17.0)
        self.fuelAnalysis = FuelAnalysis(aircraft: self.aircraft,
                                         current: flightSummary.fuelEnd,
                                         target: FuelQuantity(total: 70.0, unit:GCUnit.usgallon()),
                                         added: FuelQuantity(left: 29.0, right: 31.0, unit: self.fuelAddedUnit))
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
    
    func addLine(name : String, endurance  : Endurance) {
        self.attributedCells.append(NSAttributedString(string: name, attributes: self.titleAttributes))
        self.attributedCells.append(NSAttributedString(string: self.displayContext.formatHHMM(interval: endurance),
                                                       attributes: self.cellAttributes))
        self.attributedCells.append(NSAttributedString(string: "",
                                                       attributes: self.cellAttributes))
        self.attributedCells.append(NSAttributedString(string: "",
                                                       attributes: self.cellAttributes))
        self.sections += 1
    }
    
    func prepare() {
        
        self.attributedCells  = []
        
        for title in [ "Fuel", "Total", "Left", "Right" ] {
            self.attributedCells.append(NSAttributedString(string: title, attributes: self.titleAttributes))
        }
        self.sections = 1
        
        self.addLine(name: "Current", fuel: self.fuelAnalysis.currentFuel, unit: self.fuelTargetUnit)
        self.addLine(name: "Current Endurance", endurance: self.fuelAnalysis.currentEndurance)
        self.addSeparator()
        
        
        for (name,fuel,unit) in [
            ("Target", self.self.fuelAnalysis.targetFuel, GCUnit.usgallon()),
            ("Target Required", self.fuelAnalysis.targetAdd, self.fuelAddedUnit),
            ("Target Save", self.fuelAnalysis.targetSave, GCUnit.avgasKilogram()),
        ] {
            self.addLine(name: name, fuel: fuel, unit: unit)
        }
        
        self.addLine(name: "Target Endurance", endurance: self.fuelAnalysis.targetEndurance)
        self.addLine(name: "Target Lost Endurance", endurance: self.fuelAnalysis.targetLostEndurance)
        self.addSeparator()
        
        for (name,fuel,unit) in [
            ("Added", self.fuelAnalysis.addedfuel, self.fuelTargetUnit),
             ("", self.fuelAnalysis.addedfuel, self.fuelAddedUnit),
        ] {
            self.addLine(name: name, fuel: fuel, unit: unit)
        }

        self.addSeparator()
        for (name,fuel,unit) in [
            ("New Total", self.fuelAnalysis.addedTotal, GCUnit.usgallon()),
            ("New Save", self.fuelAnalysis.targetSave, GCUnit.avgasKilogram()),
        ] {
            self.addLine(name: name, fuel: fuel, unit: unit)
        }
        self.addLine(name: "New Endurance", endurance: self.fuelAnalysis.addedTotalEndurance)
        self.addLine(name: "Lost Endurance", endurance: self.fuelAnalysis.addedLostEndurance)
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

