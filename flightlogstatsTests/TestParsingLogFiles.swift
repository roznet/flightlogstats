//
//  flightlog1000Tests.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import XCTest
@testable import FlightLogStats
import CoreData
import OSLog
import RZFlight
import FMDB
import CoreLocation
import RZUtils
import RZData
import RZFlight

extension Logger {
    public static let test = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "test")
}

enum TestLogFileSamples : String, CaseIterable {
    case empty = "log_220414_065328______"
    case turnOnOnly = "log_220502_095923______"
    
    case taxiOnly = "log_220502_135932_EGPN"
    case taxiOnly2 = "log_220416_161856_LFQA"
    
    case smallLog = "log_small_sample"
    case smallLogFixed = "log_small_sample_fixed"
    case largeLog = "log_211204_102045_EGLL" // 5.2Mb
    
    case flight1 = "log_210623_141501_TEST1" // 2.4Mb  date with slash
    case flight2 = "log_220417_125002_LFQA" // 1.4Mb
    case flight3 = "log_220417_135002_LFAQ" // 3.2Mb
    
    case perspective = "log_210613_032326_LCPH"
    case diamond = "log_220905_064831_LGMG"
    case tbm930 = "log_230721_084427_LIRQ"
    
    static var allSampleNames : [String] { return self.allCases.map { $0.rawValue } }
    
    var url : URL? { return Bundle(for: type(of: EmptyClass())).url(forResource: self.rawValue, withExtension: "csv") }
}

class EmptyClass {}

class TestParsingLogFiles: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testFlightData() {
        self.runFlightTestData(sample: .tbm930)
        self.runFlightTestData(sample: .flight1)
        self.runFlightTestData(sample: .perspective)
        self.runFlightTestData(sample: .diamond)
    }
    
    func runFlightTestData(sample : TestLogFileSamples) {
        guard let url = sample.url,
              let data = FlightData(url: url)
        else {
            XCTAssertTrue(false)
            return
        }
       
        do {
            let summary = try FlightSummary(data: data)
            print(summary)
        }catch{
            print(error)
        }
        
        let createCollector : (FlightLogFile.Field,Double) -> ValueStats = {_,f in return ValueStats(value: f) }
        let updateCollector : (inout ValueStats?,Double) -> Void = {v,d in v?.update(double: d) }
        let speedPower = data.doubleDataFrame(for: [.GndSpd,.IAS,.E1_NP,.E1_PctPwr,.AltMSL])
        let engineField : FlightLogFile.Field  = speedPower.has(field: .E1_NP) ? .E1_NP : .E1_PctPwr
        
        if let engineOn = speedPower.dropFirst(field: engineField, matching: { $0 > 0 }),
           let moving = engineOn.dropFirst(field: .GndSpd,matching: { $0 > 0 }) {
            XCTAssertLessThan(engineOn.count, data.count)
            XCTAssertLessThanOrEqual(moving.count, engineOn.count)
        }else{
            XCTAssertTrue(false)
        }
        
        // get all field so no dropna (to match calculation of maxidx)
        let engine = data.doubleDataFrame()
        let maxindex = data.categoricalDataFrame()
        
        XCTAssertGreaterThan(engine.count, 0)
        let cylsFields : [FlightLogFile.Field] = [.E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6]
        if engine.has(fields: cylsFields) {
            for idx in 0..<engine.count {
                let x = engine.row(at: idx)
                let y = maxindex.row(at: idx)
                let cyls = cylsFields.map({ x[$0] ?? 0.0 })
                let max = cyls.max() ?? 0.0
                let maxidx = Int(cyls.firstIndex(of: max) ?? cyls.count) + 1
                
                if max.isFinite {
                    XCTAssertEqual(max,x[.E1_EGT_Max])
                    XCTAssertEqual("\(maxidx)", y[.E1_EGT_MaxIdx], "mismatch for idx=\(idx) date=\(engine.indexes[idx])" )
                }else{
                    XCTAssertEqual(y[.E1_EGT_MaxIdx], "")
                }
            }
        }
        let wind = data.doubleDataFrame(for: [.WndDirect,.WndCross,.WndSpd,.WndDr, .CRS])
        
        for idx in 0..<wind.count {
            let x = wind.row(at: idx)
            if let wndspddirect = x[.WndDirect], let wndspdcross = x[.WndCross], let wndspd = x[.WndSpd], let wnddr = x[.WndDr], let crs = x[.CRS] {
                let heading = Heading(heading: crs)
                let windDir = Heading(heading: wnddr > 0 ? wnddr : 360+wnddr)
                let runway = RunwayWindModel(runway: heading, wind: windDir, speed: Speed(speed: wndspd))
                let windCross = runway.crossWindSpeed.speed
                let windDirect = runway.headWindSpeed.speed
                
                XCTAssertEqual(windCross, wndspdcross, accuracy: 1.0)
                XCTAssertEqual(windDirect, abs(wndspddirect), accuracy: 1.0)
            }else{
                XCTAssertTrue(false)
            }
        }
        
        let identifiers = data.categoricalDataFrame(for: [.AtvWpt,.AfcsOn]).dataFrameForValueChange(fields: [.AtvWpt])

        do {
            var timings : [Date] = [Date()]
            
            let new = try data.doubleDataFrame(for: []).extractValueStats(indexes: identifiers.indexes)
            timings.append(Date())
            let generic = try data.doubleDataFrame(for: []).extract(indexes: identifiers.indexes,
                                                                 createCollector: createCollector,
                                                                 updateCollector: updateCollector)
            timings.append(Date())
            XCTAssertEqual(new.count, generic.count)
            for i in 0..<timings.count-1 {
                let start = timings[i]
                let end = timings[i+1]
                
                Logger.test.info("Timing[\(i)] = \(end.timeIntervalSince(start))")
            }
        }catch{
            XCTAssertNil(error)
        }
        
        //com changes
        let freq = data.categoricalDataFrame(for: [.COM1,.COM2]).dataFrameForValueChange(fields: [.COM1,.COM2])
        print(freq.count)
        // should loop through data/com1 and see if value same between indexes of freq
        

        // Autopilot changes, we we just change schedule function works
        let ap = data.categoricalDataFrame(for: [.AfcsOn,.RollM,.PitchM]).dataFrameForValueChange(fields: [.AfcsOn,.RollM,.PitchM])
        if let first = ap.indexes.first, let last = ap.indexes.last {
            let interval : TimeInterval = 5.0*60.0
            let range = TimeRange(start: first, end: last)
            let schedule1 = range.schedule(interval: interval)
            XCTAssertLessThanOrEqual(schedule1.first!, first)
            XCTAssertGreaterThanOrEqual(schedule1.last!, last)
            
        }else{
            XCTAssertTrue(false)
        }
    }
    
    func testTaxiOnly() {
        guard let url = TestLogFileSamples.taxiOnly2.url,
              let logfile = FlightLogFile(url: url)
        else {
            XCTAssertTrue(false)
            return
        }
        logfile.parse()
        
        let legs = logfile.legs
        let summary = logfile.flightSummary
        
        XCTAssertNotNil(summary)
        XCTAssertNotNil(legs.last)
        XCTAssertNil(summary?.flying)
        XCTAssertNotNil(summary?.moving)
        if let fuelEndR = summary?.fuelEnd.right,
           let lastFuelR = legs.last?.valueStats(field: .FQtyR) {
            XCTAssertEqual( lastFuelR.end, fuelEndR, accuracy: 1.0e-7)
        }

    }
    
    func testFlightLegExtract(){
        guard let url = TestLogFileSamples.flight3.url,
              let data = FlightData(url: url)
        else {
            XCTAssertTrue(false)
            return
        }
        
        
// from flight3 = log_220417_135002_LFAQ
//
//        17/04/2022     13:48:43
//        17/04/2022     13:54:29      PERON
//        17/04/2022     13:55:45      XORBI
//        17/04/2022     13:55:47      NEBRU
//
//        17/04/2022     14:01:18      NEBRU    32.93
//        17/04/2022     14:01:19      NEBRU    36.31    flying start
//
//        17/04/2022     14:03:00      NEBRU
//        17/04/2022     14:03:01        ABB
//
//        17/04/2022     15:06:29        OCK
//        17/04/2022     15:06:30      FINAL
//
//        17/04/2022     15:08:42      FINAL    35.7    Flying End
//        17/04/2022     15:08:43      FINAL    33.29
//
//        17/04/2022     15:12:16      FINAL
        
        do {
            let summary = try FlightSummary(data: data)
            
            let routeFull = FlightLeg.legs(from: data, byfields: [.AtvWpt], start: nil)
            let routeFlying = FlightLeg.legs(from: data, byfields: [.AtvWpt], start: summary.flying?.start, end: summary.flying?.end)
            
            let phases = FlightLeg.legs(from: data, byfields: [.FltPhase])
            var phasesCount : [FlightLeg.CategoricalValue:Int] = [:]
            for phase in phases {
                if let str = phase.categoricalValue(field: .FltPhase) {
                    if let oldCount = phasesCount[str] {
                        phasesCount[str] = oldCount + 1
                    }else{
                        phasesCount[str] = 1
                    }
                }else{
                    XCTAssertTrue(false)
                }
            }
            for name in [ "Ground", "Climb", "Cruise", "Descent"] {
                if let count = phasesCount[name] {
                    XCTAssertGreaterThanOrEqual(count, 1)
                }else{
                    XCTAssertTrue(false)
                }
            }
            
            XCTAssertLessThan(routeFlying.count, routeFull.count)
            
            if let firstFlyingLeg = routeFlying.first,
               let lastFlyingLeg = routeFlying.last,
               let flying = summary.flying {
                
                var fullRouteFirstFlyingLeg : FlightLeg? = nil
                var fullRouteLastFlyingLeg : FlightLeg? = nil

                for leg in routeFull {
                    if fullRouteFirstFlyingLeg == nil && leg.timeRange.end >= flying.start  {
                        fullRouteFirstFlyingLeg = leg
                    }
                    if leg.timeRange.start < flying.end {
                        fullRouteLastFlyingLeg = leg
                    }
                }
                
                if let fullRouteFirstFlyingLeg = fullRouteFirstFlyingLeg,
                   let fullRouteLastFlyingLeg = fullRouteLastFlyingLeg{
                    XCTAssertEqual(flying.start,firstFlyingLeg.timeRange.start)
                    XCTAssertEqual(fullRouteFirstFlyingLeg.timeRange.end,firstFlyingLeg.timeRange.end)
                    
                    XCTAssertEqual(lastFlyingLeg.timeRange.end, flying.end)
                    XCTAssertEqual(lastFlyingLeg.timeRange.start, fullRouteLastFlyingLeg.timeRange.start)
                }else{
                    XCTAssertTrue(false)
                }
                
            }else{
                XCTAssertTrue(false)
            }
        }catch{
            XCTAssertTrue(false)
        }
    }
    
    func testFlightLogFile() {
        guard let url = TestLogFileSamples.flight3.url,
              let url2 = TestLogFileSamples.flight2.url,
              let logfile = FlightLogFile(url: url),
              let logfile2 = FlightLogFile(url: url2)
        else {
            XCTAssertTrue(false)
            return
        }
        logfile.quickParse()
        let quicksummary = logfile.flightSummary
        let meta = logfile.meta(key: .system_id)
        XCTAssertNotNil(meta)
        let quickCount = logfile.count
        
        logfile.parse()
        // don't bother wtih more for logfile2, just to test in database
        logfile2.parse()
        
        let legs = logfile.legs
        let summary = logfile.flightSummary
        
        let count = logfile.count
        
        XCTAssertGreaterThan(count, quickCount)
        XCTAssertEqual(quicksummary?.startAirport, summary?.startAirport)
        // quick parse within 5min of normal
        XCTAssertLessThan(fabs(quicksummary!.flying!.elapsed - summary!.flying!.elapsed), 60.0*5.0)
        
        XCTAssertNotNil(summary)
        XCTAssertNotNil(legs.last)
        if let fuelEndR = summary?.fuelEnd.right,
           let lastFuelR = legs.last?.valueStats(field: .FQtyR) {
            XCTAssertEqual( lastFuelR.end, fuelEndR, accuracy: 1.0e-7)
        }
        
        if let first = legs.first,
           let flying = summary?.flying {
            XCTAssertEqual(flying.start, first.timeRange.start)
        }        
    }
    
    
    func testLogInterpret() throws {
        guard let url = TestLogFileSamples.flight1.url
        else {
            XCTAssertTrue(false)
            return
        }
        
        let log = FlightLogFile(url: url)!
        log.parse()
        let summary = log.flightSummary
        print( summary! )
        
        let route = log.legs
        
        let dataSource = FlightLegsDataSource(legs: route)
        let layout = TableCollectionViewLayout()
        layout.tableCollectionDelegate = dataSource
        
        let dummy = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        dummy.dataSource = dataSource
        layout.tableCollectionDelegate = dataSource
        layout.prepare()
        
        XCTAssertTrue(layout.contentSize != CGSize.zero)
        
        // check all cells fits in their row and columns
        let sections = dataSource.numberOfSections(in: dummy)
        for section in 0..<sections {
            for item in 0..<dataSource.collectionView(dummy, numberOfItemsInSection: section) {
                let indexPath = IndexPath(item: item, section: section)
                let tableSize = layout.size(at: indexPath)

                let cellSize = dataSource.size(at: indexPath)
                XCTAssertLessThanOrEqual(cellSize.width, tableSize.width)
                XCTAssertLessThanOrEqual(cellSize.height, tableSize.height)
            }
        }
    }
    
    
    func testKnownAirports(){
        let url = Bundle.main.url(forResource: "airports", withExtension: "db")
        
        XCTAssertNotNil(url)
        if let url = url {
            let db = FMDatabase(url: url)
            db.open()
            
            let known = KnownAirports(db:db)
            let cases = [ ("EGTF", 51.3504028, -0.5617803, "Woking", 1),
                          ("EGPN", 56.4537125,    -3.0180488, "Dundee", 1),
                          ("KSAF", 35.617, -106.089, "Santa Fe", 3),]
            for test in cases {
                let coord = CLLocationCoordinate2D(latitude: test.1, longitude: test.2)
                let airport = known.nearest(coord: coord, db: db)
                XCTAssertNotNil(airport)
                guard let airport = airport else { continue }
                XCTAssertEqual(airport.icao, test.0 )
                //
                XCTAssertEqual(airport.icao, test.0)
                XCTAssertEqual(airport.city, test.3)
                XCTAssertEqual(airport.runways.count, test.4)
            }
            db.close()
        }
    }
}

