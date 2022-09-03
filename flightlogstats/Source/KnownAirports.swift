//
//  KnownAirports.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 18/05/2022.
//

import Foundation
import FMDB
import KDTree
import CoreLocation
import RZFlight

class KnownAirports {
    
    struct AirportCoord : KDTreePoint {
        internal static var dimensions: Int = 2
        
        init(coord : CLLocationCoordinate2D){
            ident = ""
            latitude_deg = coord.latitude
            longiture_deg = coord.longitude
        }
        
        init(ident : String, latitude_deg : Double, longiture_deg : Double){
            self.ident = ident
            self.latitude_deg = latitude_deg
            self.longiture_deg = longiture_deg
        }
        let ident : String
        let latitude_deg : Double
        let longiture_deg : Double
        
        func kdDimension(_ dimension: Int) -> Double {
            if dimension == 0 {
                return latitude_deg
            }else{
                return longiture_deg
            }
        }
        func squaredDistance(to otherPoint: KnownAirports.AirportCoord) -> Double {
            let lat = (latitude_deg-otherPoint.latitude_deg)
            let lon = (longiture_deg-otherPoint.longiture_deg)
            return lat*lat+lon*lon
        }
    }
    let tree : KDTree<AirportCoord>
    init(db : FMDatabase){
        var points : [AirportCoord] = []
        if let res = db.executeQuery("SELECT ident,latitude_deg,longitude_deg FROM airports", withArgumentsIn: []){
            while( res.next() ){
                if let ident = res.string(forColumnIndex: 0) {
                    let lat = res.double(forColumnIndex: 1)
                    let lon = res.double(forColumnIndex: 2)
                    points.append(AirportCoord(ident: ident, latitude_deg: lat, longiture_deg: lon))
                }
            }
        }
        tree = KDTree<AirportCoord>(values: points)
    }
 
    func nearestIdent(coord : CLLocationCoordinate2D) -> String? {
        let found = tree.nearest(to: AirportCoord(coord: coord))
        return found?.ident
    }
    func nearest(coord : CLLocationCoordinate2D, db : FMDatabase) -> Airport? {
        if let found = self.nearestIdent(coord: coord){
            return try? Airport(db: db, ident: found)
        }
        return nil
    }
}
