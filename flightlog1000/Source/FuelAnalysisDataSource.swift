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
    
    weak var flightLogViewModel : FlightLogViewModel?
    let flightSummary : FlightSummary
    private var displayContext : DisplayContext
    
    private var attributedCells : [NSAttributedString] = []
    
    var frozenColumns : Int = 1
    var frozenRows : Int = 1
    
    private(set) var sections : Int = 0
    private(set) var items : Int = 4
    
    init(flightSummary : FlightSummary,
         flightViewModel : FlightLogViewModel){
        self.flightSummary = flightSummary
        self.flightLogViewModel = flightViewModel
        self.displayContext = DisplayContext()
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
        
        if let displayContext = self.flightLogViewModel?.displayContext {
            self.displayContext = displayContext
        }
        
        if let aircraft = self.flightLogViewModel?.aircraft,
           let inputs = self.flightLogViewModel?.fuelAnalysisInputs,
           let fuelTargetUnit = self.flightLogViewModel?.fuelTargetUnit,
           let fuelAddedUnit = self.flightLogViewModel?.fuelAddedUnit {
            
            let fuelAnalysis = FuelAnalysis(aircraft: aircraft,
                                            current: flightSummary.fuelEnd,
                                            inputs: inputs)
            
            
            self.attributedCells  = []
            
            for title in [ "Fuel", "Total", "Left", "Right" ] {
                self.attributedCells.append(NSAttributedString(string: title, attributes: self.titleAttributes))
            }
            self.sections = 1
            
            self.addLine(name: "Current", fuel: fuelAnalysis.currentFuel, unit: fuelTargetUnit)
            self.addLine(name: "Current Endurance", endurance: fuelAnalysis.currentEndurance)
            self.addSeparator()
            
            for (name,fuel,unit) in [
                ("Target", fuelAnalysis.targetFuel, GCUnit.usgallon()),
                ("Target Required", fuelAnalysis.targetAdd, fuelAddedUnit),
                ("Target Save", fuelAnalysis.targetSave, GCUnit.avgasKilogram()),
            ] {
                self.addLine(name: name, fuel: fuel, unit: unit)
            }
            
            self.addLine(name: "Target Endurance", endurance: fuelAnalysis.targetEndurance)
            self.addLine(name: "Target Lost Endurance", endurance: fuelAnalysis.targetLostEndurance)
            self.addSeparator()
            
            for (name,fuel,unit) in [
                ("Added", fuelAnalysis.addedFuel, fuelTargetUnit),
                ("", fuelAnalysis.addedFuel, fuelAddedUnit),
            ] {
                self.addLine(name: name, fuel: fuel, unit: unit)
            }
            
            self.addSeparator()
            for (name,fuel,unit) in [
                ("New Total", fuelAnalysis.addedTotal, GCUnit.usgallon()),
                ("New Save", fuelAnalysis.addedSave, GCUnit.avgasKilogram()),
            ] {
                self.addLine(name: name, fuel: fuel, unit: unit)
            }
            self.addLine(name: "New Endurance", endurance: fuelAnalysis.addedTotalEndurance)
            self.addLine(name: "Lost Endurance", endurance: fuelAnalysis.addedLostEndurance)
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

