//
//  TestFileGroupBy.swift
//  FlightLogStatsTests
//
//  Created by Brice Rosenzweig on 10/01/2023.
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

final class TestFileGroupBy: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func countRowsPerLogFileName(db : FMDatabase, table : String) -> [String:Int] {
        var rv : [String:Int] = [:]
        if !db.tableExists("flights") {
            return rv
        }
        
        if let res = try? db.executeQuery("SELECT LogFileName,COUNT(*) AS n FROM \(table) GROUP BY LogFileName", values: []) {
            while( res.next() ){
                if let name = res.string(forColumn: "LogFileName") {
                    let n = res.int(forColumn: "n")
                    rv[name] = Int(n)
                }
            }
        }
        return rv
    }

    func testFlightLogGroupBy() {
        let urls : [TestLogFileSamples] = [.flight3,.flight2]
        let files : [FlightLogFile] = urls.compactMap {
            guard let url = $0.url, let file = FlightLogFile(url: url) else { return nil }
            file.parse()
            return file
        }
        guard files.count == urls.count
        else {
            XCTAssertTrue(false)
            return
        }
        
        let interval : TimeInterval = 60.0
        
        let groupbys : [FlightLogFileGroupBy] = files.compactMap {
            let fixedTime = $0.legs(interval: interval)
            let export = try? FlightLogFileGroupBy.defaultExport(logFileName: $0.name, legs: fixedTime)
            return export
        }
        
        
        RZFileOrganizer.removeEditableFile("test.db")
        let dbpath = RZFileOrganizer.writeableFilePath("test.db")
        let db = FMDatabase(path: dbpath)
        db.open()
        
        var counts = self.countRowsPerLogFileName(db: db, table: "flights")
        // start empty
        XCTAssertEqual(counts.count, 0)
        
        groupbys.forEach {
            $0.save(to: db, table: "flights")
        }
        
        counts = self.countRowsPerLogFileName(db: db, table: "flights")
        
        for groupby in groupbys {
            if let fn = groupby.logFileName, let count = counts[fn] {
                XCTAssertEqual(count, groupby.values.count)
            }else{
                XCTAssertTrue(false)
            }
        }
        // save second time should replaces
        groupbys.forEach {
            $0.save(to: db, table: "flights")
        }
        
        counts = self.countRowsPerLogFileName(db: db, table: "flights")
        var totalCount = 0
        
        for groupby in groupbys {
            if let fn = groupby.logFileName, let count = counts[fn] {
                totalCount += count
                XCTAssertEqual(count, groupby.values.count)
            }else{
                XCTAssertTrue(false)
            }
        }

        let reload = FlightLogFileGroupBy(from: db, table: "flights")
        XCTAssertEqual(reload.categoricals.count, totalCount)
        XCTAssertEqual(reload.values.count, totalCount)
    }
    
}
