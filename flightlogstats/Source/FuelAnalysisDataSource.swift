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
    
    typealias Endurance = AircraftPerformance.Endurance
    
    weak var flightLogViewModel : FlightLogViewModel?
    let flightSummary : FlightSummary
    private var displayContext : DisplayContext
    
    private let columnsHeaders = [ "Fuel", "Total", "Left", "Right", "Totalizer" ]
    
    init(flightSummary : FlightSummary,
         flightViewModel : FlightLogViewModel){
        self.flightSummary = flightSummary
        self.flightLogViewModel = flightViewModel
        self.displayContext = DisplayContext()
        
        super.init(rows: 0, columns: self.columnsHeaders.count, frozenColumns: 1, frozenRows: 1)
    }
    
    //MARK: - delegate
    
    var titleAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.boldSystemFont(ofSize: 14.0)]
    var cellAttributes : [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize: 14.0)]
    
    func addSeparator() {
        for _ in 0..<self.columnsCount {
            self.cellHolders.append(CellHolder(string: "", attributes: self.titleAttributes))
        }
        self.rowsCount += 1
    }

    func adaptedName(name : String) -> String {
        if self.displayContext.horizontalSizeClass == .regular {
            return name
        }
        
        let short : [String:String] = [ "Target Required" : "Required",
                                        "Target Save" : "Save",
                                        "Target Mass Save" : "Mass Save",
                                        "Target Endurance" : "Endurance",
                                        "Target Lost" : "Lost",
                                        "Current Endurance" : "Endurance",
                                        "New Save" : "Save",
                                        "New Mass Save": "Mass Save",
                                        "New Endurance" : "Endurance",
                                        "Lost Endurance" : "Lost"
        ]
        if let adapted = short[name] {
            return adapted
        }
        return name
    }
    
    func addLine<UnitType>(name : String, fuel : FuelTanks<UnitType>, totalizer : FuelTanks<UnitType>, unit : UnitType, highlight : Bool = false) {
        
        self.cellHolders.append(CellHolder(string: self.adaptedName(name: name), attributes: self.titleAttributes))
        var geoIndex = 1
        let converted = fuel.converted(to: unit)
        for measurement in [converted.totalMeasurement,
                            converted.leftMeasurement,
                            converted.rightMeasurement,
                            totalizer.converted(to: unit).totalMeasurement] {
            if measurement.value == 0.0 {
                self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
            }else{
                let attributes : [NSAttributedString.Key:Any]? = highlight ? self.titleAttributes : nil
                let dv = displayContext.displayedValue(field: .FQtyT, measurement: measurement.measurementDimension, providedUnit: true)
                dv.adjust(geometry: self.geometries[geoIndex], numberAttribute: attributes)
                self.cellHolders.append(dv.cellHolder(attributes: attributes))
            }
            geoIndex += 1
        }
        self.rowsCount += 1
    }
    
    func addLine(name : String, endurance  : Endurance, totalizer : Endurance) {
        self.cellHolders.append(CellHolder(string: self.adaptedName(name: name), attributes: self.titleAttributes))
        
        let measurement = Measurement(value: endurance, unit: UnitDuration.seconds).measurementDimension
        let measurementT = Measurement(value: totalizer, unit: UnitDuration.seconds).measurementDimension
        
        self.cellHolders.append(CellHolder(measurement: measurement, compound: DisplayContext.coumpoundHHMMFormatter))
        self.geometries[1].adjust(measurement: measurement, compound: DisplayContext.coumpoundHHMMFormatter)
        
        self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
        self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
        
        self.cellHolders.append(CellHolder(measurement: measurementT, compound: DisplayContext.coumpoundHHMMFormatter))
        self.geometries[4].adjust(measurement: measurementT, compound: DisplayContext.coumpoundHHMMFormatter)
        
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
                
        if let aircraftPerformance = self.flightLogViewModel?.aircraftPerformance,
           let inputs = self.flightLogViewModel?.fuelAnalysisInputs,
           let fuelTargetUnit = self.flightLogViewModel?.fuelTargetUnit,
           let fuelAddedUnit = self.flightLogViewModel?.fuelAddedUnit {
            
            let fuelAnalysis = FuelAnalysis(aircraftPerformance: aircraftPerformance,
                                            current: flightSummary.fuelEnd,
                                            totalizer: flightSummary.fuelTotalizer,
                                            inputs: inputs)
            
            for title in self.columnsHeaders {
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
            
            if let estimatedStart = self.flightLogViewModel?.estimatedTotalizerStart {
                self.addLine(name: "Start (Estimated)", fuel: flightSummary.fuelStart, totalizer: estimatedStart, unit: fuelTargetUnit)
                self.addSeparator()
            }
            
            
            self.addLine(name: "Current", fuel: fuelAnalysis.currentFuel, totalizer: fuelAnalysis.currentFuelTotalizer, unit: fuelTargetUnit)
            self.addLine(name: "Current Endurance", endurance: fuelAnalysis.currentEndurance, totalizer: fuelAnalysis.currentEnduranceTotalizer)
            self.addSeparator()
            
            for (name,fuel,totalizer,unit,highlight) in [
                ("Target", fuelAnalysis.targetFuel, fuelAnalysis.targetFuel, UnitVolume.aviationGallon, false),
                ("Target Required", fuelAnalysis.targetAdd, fuelAnalysis.targetAddTotalizer, fuelAddedUnit, true),
                ("Target Save", fuelAnalysis.targetSave, fuelAnalysis.targetSave, UnitVolume.aviationGallon, false),
            ] {
                self.addLine(name: name, fuel: fuel, totalizer: totalizer, unit: unit, highlight: highlight)
            }
            
            self.addLine(name: "Target Mass Save", fuel: fuelAnalysis.targetSaveMass, totalizer: fuelAnalysis.addedSaveMassTotalizer, unit: UnitMass.kilograms )
            
            self.addLine(name: "Target Endurance", endurance: fuelAnalysis.targetEndurance, totalizer: fuelAnalysis.targetEndurance)
            self.addLine(name: "Target Lost", endurance: fuelAnalysis.targetLostEndurance, totalizer: fuelAnalysis.targetLostEndurance)
            self.addSeparator()
            
            for (name,fuel,totalizer,unit) in [
                ("Added", fuelAnalysis.addedFuel, fuelAnalysis.addedFuelTotalizer, fuelTargetUnit),
                ("", fuelAnalysis.addedFuel, fuelAnalysis.addedFuelTotalizer, fuelAddedUnit),
            ] {
                self.addLine(name: name, fuel: fuel, totalizer: totalizer, unit: unit)
            }
            
            self.addSeparator()
            for (name,fuel,totalizer,unit,highlight) in [
                ("New Total", fuelAnalysis.addedTotal, fuelAnalysis.addedTotalTotalizer, UnitVolume.aviationGallon, true),
                ("New Save", fuelAnalysis.addedSave, fuelAnalysis.addedSaveTotalizer, UnitVolume.aviationGallon, false),
            ] {
                self.addLine(name: name, fuel: fuel, totalizer: totalizer, unit: unit, highlight: highlight)
            }
            self.addLine(name: "New Mass Save", fuel: fuelAnalysis.addedSaveMass, totalizer: fuelAnalysis.addedSaveMassTotalizer, unit: UnitMass.kilograms )
            self.addLine(name: "New Endurance", endurance: fuelAnalysis.addedTotalEndurance, totalizer: fuelAnalysis.addedTotalEnduranceTotalizer)
            self.addLine(name: "Lost Endurance", endurance: fuelAnalysis.addedLostEndurance, totalizer: fuelAnalysis.addedLostEnduranceTotalizer)
        }
   }
}

