//
//  LogDetailViewModel.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 20/06/2022.
//

import Foundation
import RZUtils
import RZUtilsUniversal
import OSLog


extension Notification.Name {
    static let flightLogViewModelChanged : Notification.Name = Notification.Name("Notification.Name.logViewModelChanged")
    static let flightLogViewModelUploadFinished : Notification.Name = Notification.Name("Notification.Name.logViewModelUploadFinished")
}

class FlightLogViewModel {
    typealias Field = FlightLogFile.Field
    
    let flightLogFileInfo : FlightLogFileRecord
   
    // Every change update state
    private var writeState : Int = 0
    private var buildState : Int = -1

    private func didWrite() {
        self.writeState += 1
    }
    private func didBuild() {
        self.buildState = self.writeState
    }
    var shouldBuild : Bool {
        return self.buildState < self.writeState
    }
    
    private func save() {
        AppDelegate.worker.async {
            self.flightLogFileInfo.ensureFuelRecord()
            if let record = self.flightLogFileInfo.fuel_record {
                record.fuelAnalysisInputs = self.fuelAnalysisInputs
                self.flightLogFileInfo.saveContext()
            }
        }
    }
    
    // MARK: - Utilities
    var progress : ProgressReport?
    
    // MARK: - Configurations and user inputs
    var displayContext : DisplayContext { didSet { self.didWrite() } }
    var fuelAnalysisInputs : FuelAnalysis.Inputs { didSet { if oldValue != self.fuelAnalysisInputs { self.didWrite() } } }
    var fuelTargetUnit : UnitVolume { didSet { if oldValue != self.fuelTargetUnit { self.didWrite() } } }
    var fuelAddedUnit : UnitVolume { didSet { if oldValue != self.fuelAddedUnit { self.didWrite() } } }
    var legsByFields : [Field] { didSet { if oldValue != self.legsByFields { self.didWrite() } } }
    
    //let aircraft : AircraftPerformance { return self.ai}
    // MARK: Outputs
    private(set) var legsDataSource : FlightLegsDataSource? = nil
    private(set) var fuelDataSource : FlightSummaryFuelDataSource? = nil
    private(set) var timeDataSource : FlightSummaryTimeDataSource? = nil
    private(set) var fuelAnalysisDataSource : FuelAnalysisDataSource? = nil
    private(set) var aircraftDataSource : AircraftSummaryDataSource? = nil
    
    var aircraftPerformance : AircraftPerformance {
        get {
            return self.flightLogFileInfo.aircraftRecord?.aircraftPerformance ?? Settings.shared.aircraftPerformance
        }
        set {
            self.flightLogFileInfo.aircraftRecord?.aircraftPerformance = newValue
        }
    }
    
    var displayIdentifier : String {
        return self.flightLogFileInfo.aircraftRecord?.displayIdentifier ?? "Unknown"
    }
    
    var airframeName : String {
        return self.flightLogFileInfo.aircraftRecord?.airframeName ?? "Unknown"
    }
    
    var fuelMaxTextLabel : String {
        let max = aircraftPerformance.fuelMax.converted(to: fuelTargetUnit)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return "max \(formatter.string(from: max.totalMeasurement))"
    }
    
    var estimatedTotalizerStart : FuelQuantity? {
        if let rv = self.flightLogFileInfo.estimatedTotalizerStart {
            return min(rv, self.aircraftPerformance.fuelMax)
        }
        return nil
    }
    
    var flystoStatus : FlightFlyStoRecord.Status {
        get {
            return self.flightLogFileInfo.flysto_record?.status ?? .ready
        }
        set {
            self.flightLogFileInfo.ensureFlyStoStatus()
            self.flightLogFileInfo.flysto_record?.status = newValue
            self.flightLogFileInfo.flysto_record?.status_date = Date()
        }
    }
    
    var savvyStatus : FlightSavvyRecord.Status {
        get {
            return self.flightLogFileInfo.savvy_record?.status ?? .ready
        }
        set {
            self.flightLogFileInfo.ensureSavvyStatus()
            self.flightLogFileInfo.savvy_record?.status = newValue
            self.flightLogFileInfo.savvy_record?.status_date = Date()
        }
    }
    var flystoStatusText : String {
        var messages : [String] = []
        if Settings.shared.savvyEnabled {
            let status = self.savvyStatus.rawValue.capitalized
            messages.append("Savvy: \(status)")
        }
        if Settings.shared.flystoEnabled {
            let status = self.flystoStatus.rawValue.capitalized
            messages.append("FlySto: \(status)")
        }
        if messages.count == 0 {
            messages.append("disabled")
        }
        return messages.joined(separator: ", ")
    }
    
    // MARK: - Setup
    init(fileInfo : FlightLogFileRecord, displayContext : DisplayContext, progress : ProgressReport? = nil){
        self.flightLogFileInfo = fileInfo
        self.progress = progress
        self.displayContext = displayContext
        self.fuelAnalysisInputs = FuelAnalysis.Inputs(targetFuel: Settings.shared.targetFuel,
                                                      addedfuel: Settings.shared.addedFuel,
                                                      totalizerStartFuel: Settings.shared.totalizerStartFuel)
        
        self.fuelTargetUnit = Settings.shared.unitTargetFuel
        self.fuelAddedUnit = Settings.shared.unitAddedFuel
        self.legsByFields = [.AtvWpt]
    }
    
    func updateFromRecord() {
        self.flightLogFileInfo.ensureFuelRecord()
        if let record = self.flightLogFileInfo.fuel_record {
            self.fuelAnalysisInputs = record.fuelAnalysisInputs
        }else{
            self.fuelAnalysisInputs = FuelAnalysis.Inputs(targetFuel: Settings.shared.targetFuel,
                                                          addedfuel: Settings.shared.addedFuel,
                                                          totalizerStartFuel: Settings.shared.totalizerStartFuel)
        }
    }

    func updateForSettings() {
        self.fuelTargetUnit = Settings.shared.unitTargetFuel
        self.fuelAddedUnit = Settings.shared.unitAddedFuel

        self.didWrite()
    }
    
    func isSameLog(as other : FlightLogFileRecord) -> Bool {
        return other.log_file_name == self.flightLogFileInfo.log_file_name
    }
    
    func isValid(target : FuelQuantity) -> Bool {
        return true
    }

    func isValid(added : FuelQuantity) -> Bool {
        if let summary = self.flightLogFileInfo.flightSummary {
            let target = added + summary.fuelEnd
            return target >= summary.fuelEnd && target < self.aircraftPerformance.fuelMax
        }else{
            return true
        }
    }
    
    func build() {
        if self.shouldBuild {
            self.progress?.update(state: .start, message: .parsingInfo)
            self.flightLogFileInfo.parseAndUpdate(progress: self.progress)
                        
            if let summary = self.flightLogFileInfo.flightSummary {
                self.fuelDataSource = FlightSummaryFuelDataSource(flightSummary: summary, displayContext: self.displayContext)
                self.fuelDataSource?.prepare()
                
                self.timeDataSource = FlightSummaryTimeDataSource(flightSummary: summary, displayContext: self.displayContext)
                self.timeDataSource?.prepare()
                
                self.fuelAnalysisDataSource = FuelAnalysisDataSource(flightSummary: summary, flightViewModel: self)
                self.fuelAnalysisDataSource?.prepare()
                
                // cheat/special case to save time, use precomputed
                if self.legsByFields == [.AtvWpt] {
                    let legs = self.flightLogFileInfo.legs
                    if legs.count > 0 {
                        let legsDataSource = FlightLegsDataSource(legs: legs, displayContext: self.displayContext)
                        self.legsDataSource = legsDataSource
                    }else{
                        self.legsDataSource = nil
                    }
                }else{
                    if let legs = self.flightLogFileInfo.flightLog?.legs(byfields: self.legsByFields) {
                        self.legsDataSource = FlightLegsDataSource(legs: legs, displayContext: self.displayContext)
                    }else{
                        self.legsDataSource = nil
                    }
                }
            }
            if let aircraftRecord = self.flightLogFileInfo.aircraftRecord {
                self.aircraftDataSource = AircraftSummaryDataSource(aircaftRecord: aircraftRecord)
            }else{
                self.aircraftDataSource = nil
            }
            
            NotificationCenter.default.post(name: .flightLogViewModelChanged, object: self)
            self.save()
            self.didBuild()
        }
        self.progress?.update(state: .complete)
    }
    
    func graphDataSerie(field : FlightLogFile.Field) -> GCStatsDataSerie? {
        if self.shouldBuild {
            return nil
        }
        
        let series = self.flightLogFileInfo.dataSerie(fields: [field])
        return series[field]
    }
    
    let colors : [UIColor] = [UIColor.systemBlue, UIColor.systemRed]
    
    func scatterDataSource(fields : [FlightLogFile.Field], leg : FlightLeg? = nil) -> GCSimpleGraphCachedDataSource? {
        if let start = self.flightLogFileInfo.flightSummary?.hobbs?.start,
           let ds = GCSimpleGraphCachedDataSource.graphDataSource(withTitle: "Plot", andXUnit: GCUnitElapsedSince(start)),
           let first = fields.suffix(2).first,
           let last = fields.suffix(2).last {
            ds.useBackgroundColor = UIColor.systemBackground
            ds.axisColor = UIColor.label
            ds.useForegroundColor = UIColor.label
            ds.xUnit = first.unit.gcUnit
            if let firstSerie = self.graphDataSerie(field: first),
               let lastSerie = self.graphDataSerie(field: last){
                
                GCStatsDataSerie.reduce(toCommonRange: firstSerie, and: lastSerie)
                let xy = GCStatsInterpFunction.xySerieFor(x: firstSerie, andY: lastSerie)
                
                if let data = GCSimpleGraphDataHolder(xy, type:gcGraphType.scatterPlot, color: self.colors.first!, andUnit: last.unit.gcUnit) {
                    ds.add(data)
                }
            }
            ds.title = fields.map { $0.rawValue }.joined(separator: " x ")
            return ds
        }
        return nil
    }
    
    func graphDataSource(fields : [FlightLogFile.Field], leg : FlightLeg? = nil) -> GCSimpleGraphCachedDataSource? {
        var colorIdx = 0
        
        if let start = self.flightLogFileInfo.flightSummary?.hobbs?.start,
           let ds = GCSimpleGraphCachedDataSource.graphDataSource(withTitle: "Plot", andXUnit: GCUnitElapsedSince(start)){
            ds.useBackgroundColor = UIColor.systemBackground
            ds.axisColor = UIColor.label
            ds.useForegroundColor = UIColor.label
            for field in fields {
                if let serie = self.graphDataSerie(field: field) {
                    let color = colors[colorIdx % colors.count]
                    
                    if let data = GCSimpleGraphDataHolder(serie, type:gcGraphType.graphLine, color: color, andUnit: field.unit.gcUnit) {
                        data.axisForSerie = UInt( colorIdx )
                        if colorIdx == 0, let leg = leg,
                           let gradientSerie = GCStatsDataSerie() {
                            for point in serie {
                                if let point = point as? GCStatsDataPoint,
                                   let date = point.date() {
                                    if date >= leg.start && date <= leg.end {
                                        gradientSerie.add(GCStatsDataPoint(date: date, andValue: 1.0))
                                    }else{
                                        gradientSerie.add(GCStatsDataPoint(date: date, andValue: 0.0))
                                    }
                                }else{
                                    break
                                }
                            }
                            if gradientSerie.count() == serie.count() {
                                data.gradientColors = GCViewGradientColors([ color, color])
                                data.gradientDataSerie = gradientSerie
                                data.gradientColorsFill = GCViewGradientColors([ UIColor.clear, color.withAlphaComponent(0.3)])
                            }
                        }
                        ds.add(data)
                        colorIdx += 1
                    }
                }
            }
            ds.title = fields.map { $0.rawValue }.joined(separator: ", ")
            return ds
        }
        return nil
    }
    
    //MARK: - Servive Synchronization
    
    private var flyStoRequest : FlyStoRequests? = nil
    private var savvyRequest : SavvyRequests? = nil
    
    func startServiceSynchronization(viewController : UIViewController) {
        let flySto = Settings.shared.flystoEnabled
        let savvy = Settings.shared.savvyEnabled
        
        if let url = self.flightLogFileInfo.flightLog?.url {
            self.progress?.update(state: .start, message: .uploadingFiles)
            if flySto {
                self.flyStoRequest = FlyStoRequests(viewController: viewController, url: url)
                self.flyStoRequest?.execute() {
                    status in
                    AppDelegate.worker.async {
                        switch status {
                        case .progressing(let pct):
                            self.progress?.update(state: .progressing(pct), message: .uploadingFiles)
                            return
                        case .success,.already:
                            self.flystoStatus = .uploaded
                        case .error,.tokenExpired,.denied:
                            self.flystoStatus = .failed
                        }
                        NotificationCenter.default.post(name: .flightLogViewModelUploadFinished, object: self)
                        self.save()
                        self.progress?.update(state: .complete, message: .uploadingFiles)
                    }
                }
            }
            if savvy, let identifier = self.flightLogFileInfo.aircraftRecord?.aircraftIdentifier {
                self.savvyRequest = SavvyRequests(viewController: viewController, url: url, aircraftIdentifier: identifier)
                self.savvyRequest?.execute(){ status in
                    AppDelegate.worker.async {
                        switch status {
                        case .progressing(let pct):
                            self.progress?.update(state: .progressing(pct), message: .uploadingFiles)
                            return
                        case .success,.already:
                            self.savvyStatus = .uploaded
                        case .error,.denied,.tokenExpired:
                            self.savvyStatus = .failed
                        }
                        NotificationCenter.default.post(name: .flightLogViewModelUploadFinished, object: self)
                        self.save()
                        self.progress?.update(state: .complete, message: .uploadingFiles)
                    }
                }
            }
        }

    }
}
