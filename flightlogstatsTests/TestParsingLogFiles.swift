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
    
    static var allSampleNames : [String] { return self.allCases.map { $0.rawValue } }
 }

class TestParsingLogFiles: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testFlightData() {
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.flight1.rawValue, withExtension: "csv"),
              let data = FlightData(url: url)
        else {
            XCTAssertTrue(false)
            return
        }
        
        let createCollector : (FlightLogFile.Field,Double) -> ValueStats = {_,f in return ValueStats(value: f) }
        let updateCollector : (inout ValueStats?,Double) -> Void = {v,d in v?.update(double: d) }
        
        let speedPower = data.doubleValues(for: [.GndSpd,.IAS,.E1_PctPwr,.AltMSL])
        
        if let engineOn = speedPower.dropFirst(field: .E1_PctPwr, matching: { $0 > 0 }),
           let moving = engineOn.dropFirst(field: .GndSpd,matching: { $0 > 0 }) {
            XCTAssertLessThan(engineOn.count, data.count)
            XCTAssertLessThan(moving.count, engineOn.count)
        }else{
            XCTAssertTrue(false)
        }
        
        let engine = data.doubleValues(for: [.E1_EGT_Max,.E1_EGT_MaxIdx,.E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6])
        
        XCTAssertGreaterThan(engine.count, 0)
        for idx in 0..<engine.count {
            let x = engine.fieldsValues(at: idx)
            let cyls = [.E1_EGT1,.E1_EGT2,.E1_EGT3,.E1_EGT4,.E1_EGT5,.E1_EGT6].map({ x[$0] ?? 0.0 })
            let max = cyls.max() ?? 0.0
            let maxidx = cyls.firstIndex(of: max) ?? cyls.count
            
            XCTAssertEqual(max,x[.E1_EGT_Max])
            XCTAssertEqual(Double(maxidx)+1.0, x[.E1_EGT_MaxIdx])
        }
        
        let wind = data.doubleValues(for: [.WndDirect,.WndCross,.WndSpd,.WndDr, .CRS])
        
        for idx in 0..<wind.count {
            let x = wind.fieldsValues(at: idx)
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
        let group  = FlightGroupedData()
        do {
            
            let rv = try group.groupBy(data: data, interval: 60.0)
            
            let raw = data.doubleValues(for: rv.fields.map { $0.field } )
            
            let rv_e = try raw.extract(indexes: rv.indexes,
                        createCollector: createCollector,
                        updateCollector: updateCollector
            )
            
            
            XCTAssertEqual(rv.count, rv_e.count)
        }catch{
            XCTAssertNil(error)
        }
        
        let identifiers = data.categoricalValues(for: [.AtvWpt,.AfcsOn]).indexesForValueChange(fields: [.AtvWpt])

        do {
            var timings : [Date] = [Date()]
            
            let old = try data.extract(dates: identifiers.indexes)
            timings.append(Date())
            let new = try data.doubleValues(for: []).extractValueStats(indexes: identifiers.indexes)
            timings.append(Date())
            let generic = try data.doubleValues(for: []).extract(indexes: identifiers.indexes,
                                                                 createCollector: createCollector,
                                                                 updateCollector: updateCollector)
            timings.append(Date())
            XCTAssertEqual(old.count, new.count)
            XCTAssertEqual(old.count, generic.count)
            for i in 0..<timings.count-1 {
                let start = timings[i]
                let end = timings[i+1]
                
                Logger.test.info("Timing[\(i)] = \(end.timeIntervalSince(start))")
            }
        }catch{
            XCTAssertNil(error)
        }
        
        let freq = data.categoricalValues(for: [.COM1,.COM2]).indexesForValueChange(fields: [.COM1,.COM2])
        print(freq.count)
        
        let ap = data.categoricalValues(for: [.AfcsOn,.RollM,.PitchM]).indexesForValueChange(fields: [.AfcsOn,.RollM,.PitchM])
        let apFixedSchedule = ap.indexes.regularShedule(interval: 60.0)
        //let values = 
        
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
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.taxiOnly2.rawValue, withExtension: "csv"),
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
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.flight3.rawValue, withExtension: "csv"),
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
            
            let routeFull = FlightLeg.legs(from: data, start: nil)
            let routeFlying = FlightLeg.legs(from: data, start: summary.flying?.start, end: summary.flying?.end)
            
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
                    XCTAssertEqual(firstFlyingLeg.waypoint,fullRouteFirstFlyingLeg.waypoint)
                    
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
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.flight3.rawValue, withExtension: "csv"),
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
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.flight1.rawValue, withExtension: "csv")
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

