//
//  AppDelegate.swift
//  flightlog1000
//
//  Created by Brice Rosenzweig on 18/04/2022.
//

import UIKit
import RZFlight
import FMDB
import OSLog
import RZUtilsSwift

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    public static let worker = DispatchQueue(label: "net.ro-z.flightlogstats.worker")
    public static let queue = OperationQueue()
    
    private let keepOrganizer = FlightLogOrganizer.shared
    public static var db : FMDatabase = FMDatabase()
    public static var knownAirports : KnownAirports? = nil
    public static var knownWaypoints : KnownWaypoints? = nil
    public static let errorManager : ErrorManager = ErrorManager()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        AppDelegate.queue.maxConcurrentOperationCount = 2
        AppDelegate.queue.name = "net.ro-z.flightlogstats.queue"
        Secrets.shared = Secrets(url: Bundle.main.url(forResource: "secrets", withExtension: "json") )
        // nav.db carries airports, runways and European waypoints in the schema
        // RZFlight's model code reads (icao_code / airport_icao). It replaces the
        // old ourairports airports.db, which had no waypoints and used the
        // pre-rename column names. Rebuild it with python/make_nav_db.py.
        AppDelegate.db =  FMDatabase(url: Bundle.main.url(forResource: "nav", withExtension: "db"))
        AppDelegate.db.open()
        
        AppDelegate.worker.async {
            AppDelegate.knownAirports = KnownAirports(db: AppDelegate.db)
            AppDelegate.knownWaypoints = KnownWaypoints(db: AppDelegate.db)
        }
        
        Settings.registerDefaults()
        Settings.removeObsoleteKeys()

        AppDelegate.worker.async {
            //#warning("Don't checkin")
            //FlightLogOrganizer.shared.deleteAndResetDatabase()
            //FlightLogOrganizer.shared.deleteAndResetCloudDatabase()
            FlightLogOrganizer.shared.loadFromContainer()
            FlightLogOrganizer.shared.addMissingRecordsFromLocal()
        }
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }

}

