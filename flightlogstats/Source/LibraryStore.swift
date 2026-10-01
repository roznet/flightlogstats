//
//  LibraryStore.swift
//  FlightLogStats
//
//  The Core Data stores: Derived (parsed from the files, local) and UserState (what only
//  the user or FlySto knows, synced by CloudKit), the one-time split of the old single
//  store, and the clean up of duplicates two devices created before they synced.
//

import Foundation
import CoreData
import OSLog

/// A tombstone: the log was deleted, on any device; import and sync skip it.
class HiddenLog : NSManagedObject {
}

enum LibraryStore {
    static let derivedStoreName = "FlightLogDerived.sqlite"
    static let userStateStoreName = "FlightLogUserState.sqlite"
    /// the single store of model versions 1 to 3
    static let legacyStoreName = "FlightLogModel.sqlite"
    static let legacyBackupName = "FlightLogModel-v3-backup.sqlite"
    static let cloudKitContainer = "iCloud.net.ro-z.flightlogstats.records"

    static let derivedConfiguration = "Derived"
    static let userStateConfiguration = "UserState"

    /// Off when the app hosts unit tests: an unsigned build (CI, CODE_SIGNING_ALLOWED=NO)
    /// has no iCloud entitlement and CloudKit traps at launch, and tests should not sync
    /// anyway. DEBUG `-FLSNoCloudKit YES` turns it off too (UI tests, unsigned runs).
    static var cloudKitEnabled : Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
#if DEBUG
        if UserDefaults.standard.bool(forKey: "FLSNoCloudKit") {
            return false
        }
#endif
        return true
    }

    static func descriptions(directory : URL, cloudKit : Bool) -> [NSPersistentStoreDescription] {
        let derived = NSPersistentStoreDescription(url: directory.appendingPathComponent(Self.derivedStoreName))
        derived.configuration = Self.derivedConfiguration

        let userState = NSPersistentStoreDescription(url: directory.appendingPathComponent(Self.userStateStoreName))
        userState.configuration = Self.userStateConfiguration
        // CloudKit mirroring needs history; remote changes tell the organizer to reload
        userState.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        userState.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        if cloudKit {
            userState.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudKitContainer)
        }
        return [derived, userState]
    }

    /// The two stores in one container. Loads synchronously; errors are logged.
    static func makeContainer(model : NSManagedObjectModel, directory : URL, cloudKit : Bool) -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "FlightLogModel", managedObjectModel: model)
        container.persistentStoreDescriptions = Self.descriptions(directory: directory, cloudKit: cloudKit)
        container.loadPersistentStores { description, error in
            if let error = error {
                Logger.app.error("Failed to load \(description.configuration ?? "") store \(error.localizedDescription)")
            }else{
                Logger.app.info("Loaded \(description.configuration ?? "") store \(description.url?.lastPathComponent ?? "")")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return container
    }

    //MARK: - Split of the old single store

    /// True while the old single store is still there: it is renamed only once its
    /// copy is saved, so a copy interrupted (app stopped) runs again at the next launch.
    static func needsLegacyMigration(directory : URL) -> Bool {
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(Self.legacyStoreName).path)
    }

    /// Model version 3, the last with one store, with plain managed objects: the record
    /// classes belong to the current model.
    static func legacyModel() -> NSManagedObjectModel? {
        guard let url = Bundle(for: FlightLogOrganizer.self).url(forResource: "FlightLogModel 3", withExtension: "mom", subdirectory: "FlightLogModel.momd"),
              let model = NSManagedObjectModel(contentsOf: url) else { return nil }
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        return model
    }

    struct LegacyCopy : Equatable {
        var logs = 0
        var aircraft = 0
        var fuel = 0
        var uploads = 0
    }

    /// Copy the old store (model 1 to 3, migrated to 3 on open) into `context`, then move
    /// the old files aside as a backup. Derived records are copied too, so nothing is
    /// parsed again. Records already in the new stores (a copy saved but not renamed
    /// before the app stopped) are not copied twice.
    /// - Returns: what was copied, nil if the old store could not be read (it is left in place)
    static func migrateLegacy(directory : URL, into context : NSManagedObjectContext) -> LegacyCopy? {
        let url = directory.appendingPathComponent(Self.legacyStoreName)
        guard let model = Self.legacyModel() else {
            Logger.app.error("No model version 3 in the bundle, old store not copied")
            return nil
        }
        let legacy = NSPersistentContainer(name: "FlightLogModelLegacy", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        legacy.persistentStoreDescriptions = [description]
        var loadError : Error? = nil
        legacy.loadPersistentStores { _, error in loadError = error }
        if let error = loadError {
            Logger.app.error("Failed to open the old store \(error.localizedDescription)")
            return nil
        }
        defer {
            for store in legacy.persistentStoreCoordinator.persistentStores {
                try? legacy.persistentStoreCoordinator.remove(store)
            }
        }

        var copy = LegacyCopy()
        let source = legacy.viewContext
        func fetch(_ entity : String) -> [NSManagedObject] {
            return (try? source.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))) ?? []
        }
        func insert(_ entity : String, from object : NSManagedObject) -> NSManagedObject {
            let rv = NSEntityDescription.insertNewObject(forEntityName: entity, into: context)
            let keys = Set(rv.entity.attributesByName.keys)
            for (name,_) in object.entity.attributesByName where keys.contains(name) {
                rv.setValue(object.value(forKey: name), forKey: name)
            }
            if keys.contains("uuid") {
                rv.setValue(UUID().uuidString, forKey: "uuid")
            }
            return rv
        }
        /// the log a per-log record belonged to: its own name, else its relationship's
        func logName(_ object : NSManagedObject) -> String? {
            if let name = object.value(forKey: "log_file_name") as? String {
                return name
            }
            return (object.value(forKey: "log_file_record") as? NSManagedObject)?.value(forKey: "log_file_name") as? String
        }

        /// keys already in the new stores
        func existing(_ entity : String, key : String) -> Set<String> {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            let objects = (try? context.fetch(request)) ?? []
            return Set(objects.compactMap { $0.value(forKey: key) as? String })
        }
        
        var logNames = existing("FlightLogFileRecord", key: "log_file_name")
        for log in fetch("FlightLogFileRecord") {
            guard let name = log.value(forKey: "log_file_name") as? String, logNames.insert(name).inserted else { continue }
            _ = insert("FlightLogFileRecord", from: log)
            copy.logs += 1
        }
        var systemIds = existing("AircraftRecord", key: "system_id")
        for aircraft in fetch("AircraftRecord") {
            guard let systemId = aircraft.value(forKey: "system_id") as? String, systemIds.insert(systemId).inserted else { continue }
            _ = insert("AircraftRecord", from: aircraft)
            copy.aircraft += 1
        }
        for (entity, count) in [("FlightFuelRecord", \LegacyCopy.fuel), ("FlightFlyStoRecord", \LegacyCopy.uploads)] {
            var names = existing(entity, key: "log_file_name")
            for record in fetch(entity) {
                guard let name = logName(record), names.insert(name).inserted else { continue }
                let rv = insert(entity, from: record)
                rv.setValue(name, forKey: "log_file_name")
                copy[keyPath: count] += 1
            }
        }
        do {
            try context.save()
        }catch{
            Logger.app.error("Failed to save the copy of the old store \(error.localizedDescription)")
            context.rollback()
            return nil
        }

        // keep the old files as a backup, out of the way of the next launch
        for suffix in ["", "-wal", "-shm"] {
            let from = directory.appendingPathComponent(Self.legacyStoreName + suffix)
            let to = directory.appendingPathComponent(Self.legacyBackupName + suffix)
            if FileManager.default.fileExists(atPath: from.path) {
                try? FileManager.default.removeItem(at: to)
                try? FileManager.default.moveItem(at: from, to: to)
            }
        }
        Logger.app.info("Split the old store: \(copy.logs) logs, \(copy.aircraft) aircraft, \(copy.fuel) fuel, \(copy.uploads) uploads")
        return copy
    }

    //MARK: - Duplicates

    /// One record per key. Two devices can each create the record for the same log or
    /// aircraft before they sync; every device must keep the same one, so the choice
    /// depends only on synced values: `isBetter` first, then the smallest uuid.
    ///
    /// - Returns: the record kept for each key, and the others (to delete)
    static func deduplicate<T : NSManagedObject>(_ objects : [T],
                                                 key : (T) -> String?,
                                                 isBetter : (T, T) -> Bool) -> (kept : [String:T], duplicates : [T]) {
        var kept : [String:T] = [:]
        var duplicates : [T] = []
        for object in objects {
            guard let key = key(object) else { continue }
            guard let current = kept[key] else {
                kept[key] = object
                continue
            }
            if Self.prefer(object, over: current, isBetter: isBetter) {
                duplicates.append(current)
                kept[key] = object
            }else{
                duplicates.append(object)
            }
        }
        return (kept, duplicates)
    }

    private static func prefer<T : NSManagedObject>(_ a : T, over b : T, isBetter : (T, T) -> Bool) -> Bool {
        if isBetter(a, b) { return true }
        if isBetter(b, a) { return false }
        let ua = a.value(forKey: "uuid") as? String ?? ""
        let ub = b.value(forKey: "uuid") as? String ?? ""
        return ua < ub
    }

    /// Later user edit wins.
    static func isBetter(_ a : FlightFuelRecord, _ b : FlightFuelRecord) -> Bool {
        return (a.last_entered ?? .distantPast) > (b.last_entered ?? .distantPast)
    }

    /// Uploaded wins (it is final), then the later status.
    static func isBetter(_ a : FlightFlyStoRecord, _ b : FlightFlyStoRecord) -> Bool {
        let au = a.status == .uploaded, bu = b.status == .uploaded
        if au != bu { return au }
        return (a.status_date ?? .distantPast) > (b.status_date ?? .distantPast)
    }

    /// Later user edit (registration, performance) wins.
    static func isBetter(_ a : AircraftRecord, _ b : AircraftRecord) -> Bool {
        return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
    }

    /// Earliest deletion wins (they mean the same).
    static func isBetter(_ a : HiddenLog, _ b : HiddenLog) -> Bool {
        return (a.hidden_date ?? .distantFuture) < (b.hidden_date ?? .distantFuture)
    }
}
