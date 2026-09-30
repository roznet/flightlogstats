//
//  TestOrganizer.swift
//  flightlog1000Tests
//
//  Created by Brice Rosenzweig on 03/06/2022.
//

import XCTest
@testable import FlightLogStats
import CoreData
import OSLog
import RZFlight
import FMDB
import CoreLocation
import RZUtils

class TestOrganizer: XCTestCase {
    
    func prepareAndClearFolder(url : URL) -> Bool {
        var isDirectory : ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else{
                Logger.test.error("\(url.path) is not a directory")
                return false
            }
            
            let keys : [URLResourceKey] = [.nameKey, .isDirectoryKey]
            
            guard let fileList = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
                return false
            }
            
            for case let file as URL in fileList {
                do {
                    if FileManager.default.fileExists(atPath: file.path) {
                        try FileManager.default.removeItem(at: file)
                    }
                }catch{
                    Logger.test.error("Failed to remove file for testing \(error.localizedDescription)")
                    return false
                }
            }
            
        }else{ // does not exist, create
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            }catch{
                Logger.test.error("Failed to create directory \(url.path)")
                return false
            }
        }
        return true
    }
    
    /// quick helper to find log file
    /// - Parameter dirurl: url to search
    /// - Returns: list of found files
    func findLocalLogFiles(url : URL, types : [String.LogFileType] ) -> [URL] {
        var found : [URL] = []
        
        var isDirectory : ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let keys : [URLResourceKey] = [.nameKey, .isDirectoryKey]
                
                guard let fileList = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
                    return []
                }
                
                for case let file as URL in fileList {
                    if  types.contains(file.logFileType) {
                        found.append(file)
                    }
                }
            }
        }
        return found
    }
    
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
   
    // order array of URL by guessed date if possible
    func orderLogsByDate(urls : [URL]) -> [URL] {
        var ordered : [URL] = []
        for url in urls {
            if url.isLogFileTestFileToSkip {
                continue
            }
            if url.logFileGuessedDate != nil {
                ordered.append(url)
            }
        }
        ordered.sort {
            $0.logFileGuessedDate! < $1.logFileGuessedDate!
        }
        return ordered
    }
    /// The `+` import: files copied into the library, records created, then fully parsed
    /// in the background without blocking the caller.
    func testImportCreatesRecordsAndParses() async throws {
        let bundle = try XCTUnwrap(Bundle(for: type(of: self)).resourceURL)
        let organizer = try XCTUnwrap(self.createOrganizerWithMemoryContainer(localFolderName: "testImport", cloudFolderName: nil))
        let card = FileManager.default.temporaryDirectory.appendingPathComponent("testImportCard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: card.appendingPathComponent("data_log"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: card) }
        let logs = TestLogLibrary.logs
        for name in logs {
            try FileManager.default.copyItem(at: bundle.appendingPathComponent(name), to: card.appendingPathComponent("data_log").appendingPathComponent(name))
        }
        try FileManager.default.copyItem(at: bundle.appendingPathComponent(TestLogLibrary.rpt), to: card.appendingPathComponent(TestLogLibrary.rpt))
        
        let steps = Steps()
        let added = await organizer.importLogs(from: [card], selection: .allMissingFromFolder) { step in
            steps.append(step)
        }
        XCTAssertEqual(Set(added), Set(logs))
        XCTAssertEqual(organizer.count, logs.count)
        XCTAssertEqual(organizer.aircraftCount, 1)
        XCTAssertTrue(organizer.libraryFolder == organizer.localFolder)
        for name in logs {
            XCTAssertTrue(FileManager.default.fileExists(atPath: organizer.localFolder.appendingPathComponent(name).path))
        }
        
        // the full parse runs in batches on worker
        let deadline = Date().addingTimeInterval(60)
        while AppDelegate.worker.sync(execute: { organizer.isUpdatingRecords }) && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        for record in organizer.flightLogFileRecords(request: .all) {
            XCTAssertFalse(record.requiresParsing, record.log_file_name ?? "")
        }
        let flight = try XCTUnwrap(organizer[TestLogFileSamples.flight2.rawValue + ".csv"])
        XCTAssertEqual(flight.recordStatus, .parsed)
        XCTAssertNotNil(flight.aircraftRecord)
        
        let recorded = steps.all.contains { if case .recorded(let names) = $0 { return Set(names) == Set(logs) } else { return false } }
        XCTAssertTrue(recorded)
        
        // importing again finds nothing new
        let again = await organizer.importLogs(from: [card], selection: .allMissingFromFolder)
        XCTAssertTrue(again.isEmpty)
        
        // deleting removes the record and the library file
        organizer.delete(info: flight)
        AppDelegate.worker.sync {}
        XCTAssertNil(organizer[flight.log_file_name ?? ""])
        XCTAssertEqual(organizer.count, logs.count - 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: organizer.localFolder.appendingPathComponent(TestLogFileSamples.flight2.rawValue + ".csv").path))
    }
    
    final class Steps : @unchecked Sendable {
        private let lock = NSLock()
        private var steps : [FlightLogOrganizer.ImportProgress] = []
        var all : [FlightLogOrganizer.ImportProgress] { self.lock.withLock { self.steps } }
        func append(_ step : FlightLogOrganizer.ImportProgress) { self.lock.withLock { self.steps.append(step) } }
    }
    
    /// Savvy removal: a library saved with model version 1 (with `FlightSavvyRecord` and
    /// `savvy_record`) opens with the current model by lightweight migration, keeping the
    /// logs and their FlySto status.
    func testModelMigrationFromVersion1() throws {
        guard let v1url = Bundle(for: FlightLogOrganizer.self).url(forResource: "FlightLogModel", withExtension: "mom", subdirectory: "FlightLogModel.momd"),
              let v1 = NSManagedObjectModel(contentsOf: v1url) else {
            XCTFail("no version 1 model in FlightLogModel.momd")
            return
        }
        XCTAssertNotNil(v1.entitiesByName["FlightSavvyRecord"])
        XCTAssertNil(FlightLogOrganizer.managedObjectModel.entitiesByName["FlightSavvyRecord"])
        // plain managed objects: the record classes belong to the current model
        for entity in v1.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("testMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let storeUrl = folder.appendingPathComponent("FlightLogModel.sqlite")
        let logName = "log_220417_125002_LFQA.csv"
        
        // an existing library, written with version 1
        let old = NSPersistentContainer(name: "FlightLogModel", managedObjectModel: v1)
        old.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeUrl)]
        var loadError : Error? = nil
        old.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        let oldContext = old.viewContext
        let log = NSEntityDescription.insertNewObject(forEntityName: "FlightLogFileRecord", into: oldContext)
        log.setValue(logName, forKey: "log_file_name")
        let flysto = NSEntityDescription.insertNewObject(forEntityName: "FlightFlyStoRecord", into: oldContext)
        flysto.setValue("uploaded", forKey: "upload_status")
        log.setValue(flysto, forKey: "flysto_record")
        let savvy = NSEntityDescription.insertNewObject(forEntityName: "FlightSavvyRecord", into: oldContext)
        savvy.setValue("uploaded", forKey: "upload_status")
        log.setValue(savvy, forKey: "savvy_record")
        try oldContext.save()
        for store in old.persistentStoreCoordinator.persistentStores {
            try old.persistentStoreCoordinator.remove(store)
        }
        
        // opened as the app does
        let current = FlightLogOrganizer.makePersistentContainer()
        let description = NSPersistentStoreDescription(url: storeUrl)
        XCTAssertTrue(description.shouldMigrateStoreAutomatically)
        XCTAssertTrue(description.shouldInferMappingModelAutomatically)
        current.persistentStoreDescriptions = [description]
        current.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError)
        
        let records : [FlightLogFileRecord] = try current.viewContext.fetch(FlightLogFileRecord.fetchRequest())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.log_file_name, logName)
        XCTAssertEqual(records.first?.flysto_record?.upload_status, "uploaded")
        
        for store in current.persistentStoreCoordinator.persistentStores {
            try current.persistentStoreCoordinator.remove(store)
        }
    }
    
    /// Savvy removal: the stored Savvy token and switch are cleared at launch.
    func testRemoveObsoleteSettings() throws {
        let suite = "net.ro-z.flightlogstats.test.obsolete"
        guard let defaults = UserDefaults(suiteName: suite) else { XCTFail(); return }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set("token", forKey: "savvy.token")
        defaults.set(true, forKey: "savvy.enabled")
        defaults.set(true, forKey: "flysto.enabled")
        Settings.removeObsoleteKeys(from: defaults)
        XCTAssertNil(defaults.object(forKey: "savvy.token"))
        XCTAssertNil(defaults.object(forKey: "savvy.enabled"))
        XCTAssertEqual(defaults.object(forKey: "flysto.enabled") as? Bool, true)
    }
    
    func testLogFileNameGuesses(){
        guard let url = Bundle(for: type(of: self)).resourceURL
        else {
            XCTAssertTrue(false)
            return
        }
        let files = self.findLocalLogFiles(url: url, types: [.log,.rpt])
        let reconstructFormatter = DateFormatter()
        reconstructFormatter.dateFormat = "yyMMdd_HHmm"
        for file in files {
            let name = file.lastPathComponent
            // special case, not a date
            if name.hasPrefix("log_small") {
                continue
            }
            if let date = name.logFileGuessedDate {
                if name.logFileType == .log {
                    let rebuildPrefix = "log_\(reconstructFormatter.string(from: date))"
                    XCTAssertTrue(name.hasPrefix(rebuildPrefix))
                }else if name.logFileType == .rpt {
                    let rebuildPrefix = "rpt_\(reconstructFormatter.string(from: date))"
                    XCTAssertTrue(name.hasPrefix(rebuildPrefix))
                }
            }else{
                XCTAssertTrue(false, "bad date for \(name)")
            }
        }
    }
    func createOrganizerWithMemoryContainer(localFolderName : String, cloudFolderName : String?) -> FlightLogOrganizer? {
        let organizer = FlightLogOrganizer()
        let writeableBase =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let writeableLocalUrl = writeableBase.appendingPathComponent(localFolderName)
        organizer.localFolder = writeableLocalUrl
        var toClean : [URL] = [writeableLocalUrl]
        if let cloudFolderName = cloudFolderName {
            let writeableCloudUrl = writeableBase.appendingPathComponent(cloudFolderName)
            toClean.append(writeableCloudUrl)
            organizer.cloudFolder = writeableCloudUrl
        }
        Logger.test.info("Cleaning test folders")
        for writeableUrl in toClean {
            guard self.prepareAndClearFolder(url: writeableUrl) else {
                return nil
            }
            Logger.test.info("Cleaned and prepared \(writeableUrl.path)")
        }
        
        let container = FlightLogOrganizer.makePersistentContainer()
        let description = NSPersistentStoreDescription()
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores() {
            (storeDescription,error) in
            if let error = error {
                Logger.test.error("Failed to load \(error.localizedDescription)")
                return
            }
        }
        organizer.persistentContainer = container
        
        let dbpath = writeableBase.appending(path: "testAggregatedData.db")
        let db = FMDatabase(url: dbpath)
        db.open()
        organizer.aggregatedData = AggregatedDataOrganizer(db: db)
        
        return organizer
    }
    func testOrganizer() {
        let expectation = self.expectation(description: "run organizer test")
        AppDelegate.worker.async {
            do {
                try self.runTestOrganizer()
            }catch{
                XCTAssertNil(error)
            }
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: 10.0)
    }
    func runTestOrganizer() throws {
        let organizer = FlightLogOrganizer()
        
        let container = FlightLogOrganizer.makePersistentContainer()
        let description = NSPersistentStoreDescription()
        description.url = URL(fileURLWithPath: "/dev/null")
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores() {
            (storeDescription,error) in
            if let error = error {
                Logger.test.error("Failed to load \(error.localizedDescription)")
            }
        }
        organizer.persistentContainer = container
        
        let expectation = XCTestExpectation(description: "container loaded")
        
        guard let url = Bundle(for: type(of: self)).url(forResource: TestLogFileSamples.flight1.rawValue, withExtension: "csv")
        else {
            XCTAssertTrue(false)
            return
        }
        
        let log = FlightLogFile(url: url)!
        log.parse()
        organizer.addMinimum(flightLogFileList: FlightLogFileList(logs: [log]))
        do {
            organizer.saveContext()
            
            XCTAssertEqual(organizer.count,1)
            
            if let info = organizer.flightLogFileRecords(request: .all).first {
                let record = FlightFuelRecord(context: container.viewContext)
                record.target_fuel = 75.0
                info.fuel_record = record
                organizer.saveContext()
            }
            let reload = FlightLogOrganizer()
            reload.persistentContainer = container
            XCTAssertEqual(reload.count,0)
            reload.loadFromContainer()
            XCTAssertEqual(reload.count,1)
            organizer.loadFromContainer()
            XCTAssertEqual(reload.count,1)
            XCTAssertNotNil(reload.flightLogFileRecords(request: .all).first?.fuel_record)
            if let info = reload.flightLogFileRecords(request: .all).first,
               let record = info.fuel_record {
                XCTAssertEqual( record.target_fuel, 75.0)
                record.target_fuel = 80.0
                organizer.saveContext()
            }
            
            let reload2 = FlightLogOrganizer()
            reload2.persistentContainer = container
            XCTAssertEqual(reload2.count,0)
            reload2.loadFromContainer()
            XCTAssertNotNil(reload2.flightLogFileRecords(request: .all).first?.fuel_record)
            if let info = reload2.flightLogFileRecords(request: .all).first,
               let record = info.fuel_record {
                XCTAssertEqual( record.target_fuel, 80.0)
            }
        }
        expectation.fulfill()
    }
}

extension URL {
    var isLogFileTestFileToSkip : Bool {
        return self.isLogFile && self.lastPathComponent.hasPrefix("log_small")
    }
}
