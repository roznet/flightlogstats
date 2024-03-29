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
    
    let flightLogFileRecord : FlightLogFileRecord
   
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
    
    func save() {
        AppDelegate.worker.async {
            self.flightLogFileRecord.ensureFuelRecord()
            if let record = self.flightLogFileRecord.fuel_record {
                record.fuelAnalysisInputs = self.fuelAnalysisInputs
                self.flightLogFileRecord.saveContext()
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
            return self.flightLogFileRecord.aircraftRecord?.aircraftPerformance ?? Settings.shared.aircraftPerformance
        }
        set {
            self.flightLogFileRecord.aircraftRecord?.aircraftPerformance = newValue
        }
    }
    
    var displayIdentifier : String {
        return self.flightLogFileRecord.aircraftRecord?.displayIdentifier ?? "Unknown"
    }
    
    var airframeName : String {
        return self.flightLogFileRecord.aircraftRecord?.airframeName ?? "Unknown"
    }
    
    var fuelMaxTextLabel : String {
        let max = aircraftPerformance.fuelMax.converted(to: fuelTargetUnit)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits = 0
        return "max \(formatter.string(from: max.totalMeasurement))"
    }
    
    var estimatedTotalizerStart : FuelQuantity? {
        if let rv = self.flightLogFileRecord.estimatedTotalizerStart {
            return min(rv, self.aircraftPerformance.fuelMax)
        }
        return nil
    }
    
    var savvyStatus : FlightSavvyRecord.Status {
        return self.flightLogFileRecord.savvyStatus
    }
    var savvyUpdateDate : Date? {
        return self.flightLogFileRecord.savvyUpdateDate
    }
    var uploadStatusText : String {
        var messages : [String] = []
        if Settings.shared.flystoEnabled {
            let status = self.flystoStatus.rawValue.capitalized
            messages.append("FlySto: \(status)")
        }
        if Settings.shared.savvyEnabled {
            let status = self.savvyStatus.rawValue.capitalized
            messages.append("Savvy: \(status)")
        }
        if messages.count == 0 {
            messages.append("disabled")
        }
        return messages.joined(separator: ", ")
    }
    
    // MARK: - Setup
    init(fileInfo : FlightLogFileRecord, displayContext : DisplayContext, progress : ProgressReport? = nil){
        self.flightLogFileRecord = fileInfo
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
        self.flightLogFileRecord.ensureFuelRecord()
        if let record = self.flightLogFileRecord.fuel_record {
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
        return other.log_file_name == self.flightLogFileRecord.log_file_name
    }
    
    func isValid(target : FuelQuantity) -> Bool {
        return true
    }

    func isValid(added : FuelQuantity) -> Bool {
        if let summary = self.flightLogFileRecord.flightSummary {
            let target = added + summary.fuelEnd
            return target >= summary.fuelEnd && target < self.aircraftPerformance.fuelMax
        }else{
            return true
        }
    }
    
    func build() {
        if self.shouldBuild {
            self.progress?.update(state: .start, message: .parsingInfo)
            self.flightLogFileRecord.parseAndUpdate(progress: self.progress)
                        
            if let summary = self.flightLogFileRecord.flightSummary {
                self.fuelDataSource = FlightSummaryFuelDataSource(flightSummary: summary, displayContext: self.displayContext)
                self.fuelDataSource?.prepare()
                
                self.timeDataSource = FlightSummaryTimeDataSource(flightSummary: summary, displayContext: self.displayContext)
                self.timeDataSource?.prepare()
                
                self.fuelAnalysisDataSource = FuelAnalysisDataSource(flightSummary: summary, flightViewModel: self)
                self.fuelAnalysisDataSource?.prepare()
                
                // cheat/special case to save time, use precomputed
                if self.legsByFields == [.AtvWpt] {
                    let legs = self.flightLogFileRecord.legs
                    if legs.count > 0 {
                        let legsDataSource = FlightLegsDataSource(legs: legs, displayContext: self.displayContext)
                        self.legsDataSource = legsDataSource
                    }else{
                        self.legsDataSource = nil
                    }
                }else{
                    if let legs = self.flightLogFileRecord.flightLog?.legs(byfields: self.legsByFields) {
                        self.legsDataSource = FlightLegsDataSource(legs: legs, displayContext: self.displayContext)
                    }else{
                        self.legsDataSource = nil
                    }
                }
            }
            if let aircraftRecord = self.flightLogFileRecord.aircraftRecord {
                self.aircraftDataSource = AircraftSummaryDataSource(aircaftRecord: aircraftRecord)
            }else{
                self.aircraftDataSource = nil
            }
            AppDelegate.worker.async {
                self.flightLogFileRecord.ensureFuelRecord()
            }
            NotificationCenter.default.post(name: .flightLogViewModelChanged, object: self)
            self.didBuild()
        }
        self.progress?.update(state: .complete)
    }
    
    func graphDataSerie(field : FlightLogFile.Field) -> GCStatsDataSerie? {
        if self.shouldBuild {
            return nil
        }
        
        let series = self.flightLogFileRecord.dataSerie(fields: [field])
        return series[field]
    }
    
    let colors : [UIColor] = [UIColor.systemBlue, UIColor.systemRed]
    
    func scatterDataSource(fields : [FlightLogFile.Field], leg : FlightLeg? = nil) -> GCSimpleGraphCachedDataSource? {
        if let start = self.flightLogFileRecord.flightSummary?.hobbs?.start,
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
        
        if let start = self.flightLogFileRecord.flightSummary?.hobbs?.start,
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
    
    private var flyStoRequest : FlyStoUploadRequest? = nil
    private var savvyRequest : SavvyRequest? = nil
    var flystoStatus : FlightFlyStoRecord.Status  { return self.flightLogFileRecord.flystoStatus }
    var flystoUpdateDate : Date? { return self.flightLogFileRecord.flystoUpdateDate }
    
    func startServiceSynchronization(viewController : UIViewController, force : Bool = false) {
        // don't bother if no network
        guard RZSystemInfo.networkAvailable() else {
            Logger.net.info("No network available, skipping uploads")
            return
        }
        
        if self.flightLogFileRecord.url != nil {
            RequestQueue.shared.add(record: self.flightLogFileRecord, viewController: viewController, force: force, progress: self.progress)
        }
    }
    private var flyStoLogFileRequest : FlyStoLogFilesRequest? = nil
    
    func startFlyStoLogFileUrl(viewController : UIViewController, first : Bool = true) {
        var started = false
        if (self.flystoStatus == .uploaded && !self.flightLogFileRecord.flystoLogFilesInformationAvailable) || self.flystoStatus == .ready {
            guard first else { return };
            
            if let url = self.flightLogFileRecord.url {
                Logger.ui.info("Missing flySto fileId, uploading")
                self.progress?.update(state: .start, message: .uploadingFiles)
                started = true
                self.flyStoRequest = FlyStoUploadRequest(viewController: viewController, url: url)
                self.flyStoRequest?.execute() {
                    status,req in
                    AppDelegate.worker.async {
                        self.flightLogFileRecord.flyStoUploadCompletion(status: status, request: req)
                        NotificationCenter.default.post(name: .flightLogViewModelUploadFinished, object: self)
                        self.save()
                        Logger.ui.info("should have flySto fileId, trying again")
                        self.startFlyStoLogFileUrl(viewController: viewController, first: false)
                    }
                }
            }
        }
        if (self.flystoStatus == .uploaded && self.flightLogFileRecord.flystoLogFilesInformationAvailable),
           let req = self.flightLogFileRecord.flyStoLogFilesRequest(viewController: viewController) {
            if !started {
                self.progress?.update(state: .start, message: .uploadingFiles)
            }
            req.execute() { status, req in
                if let req = req as? FlyStoLogFilesRequest,
                   let url = req.url {
                    Logger.ui.info("got flysto url: \(url)")
                    DispatchQueue.main.async {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }
}
