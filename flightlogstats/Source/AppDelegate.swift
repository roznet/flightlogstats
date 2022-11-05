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

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    public static let worker = DispatchQueue(label: "net.ro-z.flightlog1000.worker")
    private let keepOrganizer = FlightLogOrganizer.shared
    public static var db : FMDatabase = FMDatabase()
    public static var knownAirports : KnownAirports? = nil
    public static let errorManager : ErrorManager = ErrorManager()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        Secrets.shared = Secrets(url: Bundle.main.url(forResource: "secrets", withExtension: "json") )
        AppDelegate.db =  FMDatabase(url: Bundle.main.url(forResource: "airports", withExtension: "db"))
        AppDelegate.db.open()
        
        AppDelegate.worker.async {
            AppDelegate.knownAirports = KnownAirports(db: AppDelegate.db)
        }
        
        Settings.registerDefaults()

        FlightLogOrganizer.shared.loadFromContainer()
        FlightLogOrganizer.shared.addMissingFromLocal()
        
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

