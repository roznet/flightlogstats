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
    
    static let formatter : MeasurementFormatter = { let formatter = MeasurementFormatter(); formatter.unitStyle = .medium; formatter.unitOptions = .providedUnit; return formatter }()
    func addLine(name : String, fuel : FuelQuantity, totalizer : FuelQuantity, unit : UnitVolume) {
        
        self.cellHolders.append(CellHolder(string: name, attributes: self.titleAttributes))
        var geoIndex = 1
        for measurement in [fuel.convert(to: unit).totalMeasurement,
                            fuel.convert(to: unit).leftMeasurement,
                            fuel.convert(to: unit).rightMeasurement,
                            totalizer.convert(to: unit).totalMeasurement] {
            if measurement.value == 0.0 {
                self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
            }else{
                self.geometries[geoIndex].adjust(measurement: measurement, formatter: Self.formatter)
                let newmeasurement : Measurement<Dimension> = Measurement(value: measurement.value, unit: measurement.unit as Dimension)
                self.cellHolders.append(CellHolder(measurement: newmeasurement, formatter: Self.formatter))
            }
            geoIndex += 1
        }
        self.rowsCount += 1
    }
    
    func addLine(name : String, endurance  : Endurance, totalizer : Endurance) {
        self.cellHolders.append(CellHolder(string: name, attributes: self.titleAttributes))
        let nu = endurance.numberWithUnit.convert(to: GCUnit.hobbshour())
        let nuT = totalizer.numberWithUnit.convert(to: GCUnit.hobbshour())
        
        self.cellHolders.append(CellHolder(numberWithUnit: nu))
        self.geometries[1].adjust(for: nu)
        
        self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
        self.cellHolders.append(CellHolder(string: "", attributes: self.cellAttributes))
        
        self.cellHolders.append(CellHolder(numberWithUnit: nuT))
        self.geometries[4].adjust(for: nuT)
        
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
            
            for (name,fuel,totalizer,unit) in [
                ("Target", fuelAnalysis.targetFuel, fuelAnalysis.targetFuel, UnitVolume.aviationGallon),
                ("Target Required", fuelAnalysis.targetAdd, fuelAnalysis.targetAddTotalizer, fuelAddedUnit),
                ("Target Save", fuelAnalysis.targetSave, fuelAnalysis.targetSave, UnitVolume.aviationGallon),
            ] {
                self.addLine(name: name, fuel: fuel, totalizer: totalizer, unit: unit)
            }
            
            self.addLine(name: "Target Endurance", endurance: fuelAnalysis.targetEndurance, totalizer: fuelAnalysis.targetEndurance)
            self.addLine(name: "Target Lost Endurance", endurance: fuelAnalysis.targetLostEndurance, totalizer: fuelAnalysis.targetLostEndurance)
            self.addSeparator()
            
            for (name,fuel,totalizer,unit) in [
                ("Added", fuelAnalysis.addedFuel, fuelAnalysis.addedFuelTotalizer, fuelTargetUnit),
                ("", fuelAnalysis.addedFuel, fuelAnalysis.addedFuelTotalizer, fuelAddedUnit),
            ] {
                self.addLine(name: name, fuel: fuel, totalizer: totalizer, unit: unit)
            }
            
            self.addSeparator()
            for (name,fuel,totalizer,unit) in [
                ("New Total", fuelAnalysis.addedTotal, fuelAnalysis.addedTotalTotalizer, UnitVolume.aviationGallon),
                ("New Save", fuelAnalysis.addedSave, fuelAnalysis.addedSaveTotalizer, UnitVolume.aviationGallon),
            ] {
                self.addLine(name: name, fuel: fuel, totalizer: totalizer, unit: unit)
            }
            self.addLine(name: "New Endurance", endurance: fuelAnalysis.addedTotalEndurance, totalizer: fuelAnalysis.addedTotalEnduranceTotalizer)
            self.addLine(name: "Lost Endurance", endurance: fuelAnalysis.addedLostEndurance, totalizer: fuelAnalysis.addedLostEnduranceTotalizer)
        }
   }
}

