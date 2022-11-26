//
//  FlightData+Map.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 05/08/2022.
//

import Foundation
import MapKit

extension FlightData {
    var boundingPoints : (northEast : CLLocationCoordinate2D, southWest : CLLocationCoordinate2D)? {
        
        var northEastPoint : CLLocationCoordinate2D? = nil
        var southWestPoint : CLLocationCoordinate2D? = nil
        
        guard let column = self.coordinateDataFrame(for: [.Coordinate])[.Coordinate] else { return nil }
        
        for point in column {
            let coord = point.value
            if coord.longitude <= -180.0 {
                continue
            }

            if let east = northEastPoint, let west = southWestPoint {
                if coord.latitude > east.latitude {
                    northEastPoint?.latitude = coord.latitude
                }
                if coord.longitude > east.longitude {
                    northEastPoint?.longitude = coord.longitude
                }
                if coord.latitude < west.latitude {
                    southWestPoint?.latitude = coord.latitude
                }
                if coord.longitude < west.longitude{
                    southWestPoint?.longitude = coord.longitude
                }
            }else{
                northEastPoint = coord
                southWestPoint = coord
            }
        }
        if let ne = northEastPoint, let sw = southWestPoint {
            return (northEast: ne, southWest: sw)
        }else{
            return nil
        }
    }
}

extension MKMapRect {
    init(southWest : CLLocationCoordinate2D, northEast : CLLocationCoordinate2D) {
        let neMapPoint = MKMapPoint(northEast)
        let swMapPoint = MKMapPoint(southWest)
        let rv = MKMapRect(x: swMapPoint.x, y: neMapPoint.y,
                           width: neMapPoint.x - swMapPoint.x, height: swMapPoint.y-neMapPoint.y)
        self = rv.insetBy(dx: -rv.width*0.1, dy: -rv.height*0.1)
    }
}

extension CLLocationCoordinate2D {
    func halfWay(to: CLLocationCoordinate2D) -> CLLocationCoordinate2D{
        return CLLocationCoordinate2D(latitude: (to.latitude + self.latitude)/2.0,
                                      longitude: (to.longitude + self.longitude)/2.0)
    }
}
class FlightDataMapOverlay : NSObject, MKOverlay {
    var coordinate: CLLocationCoordinate2D
    var boundingMapRect: MKMapRect

    var coordinates : DataFrame<Date,CLLocationCoordinate2D,FlightLogFile.Field>.Column
    
    var highlightTimeRange : TimeRange? = nil
    var colorChange : [Date] = []
    
    init(data : FlightData) {
        self.coordinates = data.coordinateColumn
        if let boundingPoints = data.boundingPoints {
            self.boundingMapRect = MKMapRect(southWest: boundingPoints.southWest, northEast: boundingPoints.northEast)
            self.coordinate = boundingPoints.southWest.halfWay(to: boundingPoints.northEast)
        }else{
            self.boundingMapRect = MKMapRect()
            self.coordinate = CLLocationCoordinate2D()
        }
        
        super.init()
    }
}

class FlightDataMapOverlayView : MKOverlayRenderer {
    
    enum PathState {
        case primary
        case highlight
        case secondary
    }
    
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        if let mapOverlay = self.overlay as? FlightDataMapOverlay {
            var last : CGPoint? = nil
            context.beginPath()
            context.setLineWidth( 2.0 / zoomScale )
            var pathState : PathState = .primary
            
            for point in mapOverlay.coordinates {
                let coord = point.value
                if coord.longitude <= -180.0 {
                    continue
                }
                let mapPoint = MKMapPoint(coord)
                let current = self.point(for: mapPoint)
                if let range = mapOverlay.highlightTimeRange {
                    if range.start <= point.index && pathState == .primary {
                        // start new path with new color
                        context.setStrokeColor(UIColor.systemRed.cgColor)
                        context.strokePath()
                        context.beginPath()
                        context.setLineWidth( 5.0 / zoomScale )
                        pathState = .highlight
                    }
                    if range.end <= point.index && pathState == .highlight{
                        context.setStrokeColor(UIColor.systemBlue.cgColor)
                        context.strokePath()
                        context.beginPath()
                        context.setLineWidth( 2.0 / zoomScale )
                        context.setStrokeColor(UIColor.systemRed.cgColor)
                        pathState = .primary
                    }
                }
                
                if let last = last {
                    context.move(to: last)
                    context.addLine(to: current)
                }
                last = current
            }
            if pathState == .highlight {
                context.setStrokeColor(UIColor.systemBlue.cgColor)
            }else{
                context.setStrokeColor(UIColor.systemRed.cgColor)
            }
            context.strokePath()
        }
    }
}

extension FlightLogFile {
}
