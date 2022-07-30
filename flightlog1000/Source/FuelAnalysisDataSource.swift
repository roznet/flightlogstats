//
//  FuelAnalysisDataSource.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 23/06/2022.
//

import UIKit
import OSLog
import RZUtils
import RZUtilsSwift

extension TimeInterval {
    var numberWithUnit : GCNumberWithUnit { return GCNumberWithUnit(unit: GCUnit.second(), andValue: self) }
}

class FuelAnalysisDataSource: TableDataSource {
    
    typealias Endurance = Aircraft.Endurance
    
    weak var flightLogViewModel : FlightLogViewModel?
    let flightSummary : FlightSummary
    private var displayContext : DisplayContext
    
    init(flightSummary : FlightSummary,
         flightViewModel : FlightLogViewModel){
        self.flightSummary = flightSummary
        self.flightLogViewModel = flightViewModel
        self.displayContext = DisplayContext()
        
        super.init(rows: 0, columns: 4, frozenColumns: 1, frozenRows: 1)
    }
    
    //MARK: - delegate
    
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    func addSeparator() {
        for _ in 0..<4 {
            self.cellHolders.append(CellHolder(string: "", attributes: self.titleAttributes))
        }
        self.rowsCount += 1
    }
    
    func addLine(name : String, fuel : FuelQuantity, unit : GCUnit) {
        self.cellHolders.append(CellHolder(string: name, attributes: self.titleAttributes))
        var geoIndex = 1
        for nu in [fuel.totalWithUnit.convert(to: unit),
                   fuel.leftWithUnit.convert(to: unit),
                   fuel.rightWithUnit.convert(to: unit)] {
            self.geometries[geoIndex].adjust(for: nu)
            self.cellHolders.append(CellHolder.numberWithUnit(nu))
            geoIndex += 1
        }
        self.rowsCount += 1
    }
    
    func addLine(name : String, endurance  : Endurance) {
        self.cellHolders.append(CellHolder(string: name, attributes: self.titleAttributes))
        let nu = endurance.numberWithUnit.convert(to: GCUnit.minute())
        self.cellHolders.append(CellHolder.numberWithUnit(nu))
        self.geometries[1].adjust(for: nu)
        self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
        self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
        self.rowsCount += 1
    }
    
    override func prepare() {
        self.cellHolders = []
        self.geometries = []
        
        self.cellAttributes = ViewConfig.shared.cellAttributes
        self.titleAttributes = ViewConfig.shared.titleAttributes
        
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
            
            
            
            for title in [ "Fuel", "Total", "Left", "Right" ] {
                let geometry = RZNumberWithUnitGeometry()
                geometry.defaultUnitAttribute = cellAttributes
                geometry.defaultNumberAttribute = cellAttributes
                geometry.numberAlignment = .decimalSeparator
                geometry.unitAlignment = .left
                geometry.alignment = .left
                self.geometries.append(geometry)

                self.cellHolders.append(CellHolder(string: title, attributes: self.titleAttributes))
            }
            self.rowsCount = 1
            
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
}

