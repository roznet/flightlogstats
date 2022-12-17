//
//  FlightData+Map.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 05/08/2022.
//

import Foundation
import MapKit
import RZData

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
    var highlightCoordinate: CLLocationCoordinate2D
    var highlightMapRect : MKMapRect

    var coordinates : DataFrame<Date,CLLocationCoordinate2D,FlightLogFile.Field>.Column
    
    var highlightTimeRange : TimeRange? = nil {
        didSet { self.updateBounds() }
    }
    var colorChange : [Date] = []
    
    init(data : FlightData) {
        self.coordinates = data.coordinateColumn
        
        self.boundingMapRect = MKMapRect()
        self.highlightMapRect = MKMapRect()
        self.coordinate = CLLocationCoordinate2D()
        self.highlightCoordinate = CLLocationCoordinate2D()

        super.init()
        
        self.updateBounds()
    }
    
    private func updateBounds() {
        
        var southWest : CLLocationCoordinate2D? = nil
        var northEast : CLLocationCoordinate2D? = nil

        var highlightSouthWest : CLLocationCoordinate2D? = nil
        var highlightNorthEast : CLLocationCoordinate2D? = nil
        
        for point in coordinates {
            let coord = point.value
            if coord.longitude <= -180.0 || coord.latitude <= -180.0 {
                continue
            }

            if southWest == nil {
                southWest = coord
                northEast = coord
                
                continue
            }
            
            southWest = CLLocationCoordinate2D(latitude: min(southWest!.latitude,coord.latitude),
                                               longitude: min(southWest!.longitude,coord.longitude))
            northEast = CLLocationCoordinate2D(latitude: max(northEast!.latitude,coord.latitude),
                                               longitude: max(northEast!.longitude,coord.longitude))

            if let range = highlightTimeRange {
                if (range.start <= point.index) && (point.index <= range.end) {
                    if highlightSouthWest == nil {
                        highlightSouthWest = coord
                        highlightNorthEast = coord
                    }else{
                        highlightSouthWest = CLLocationCoordinate2D(latitude: min(highlightSouthWest!.latitude,coord.latitude),
                                                                    longitude: min(highlightSouthWest!.longitude,coord.longitude))
                        highlightNorthEast = CLLocationCoordinate2D(latitude: max(highlightNorthEast!.latitude,coord.latitude),
                                                                    longitude: max(highlightNorthEast!.longitude,coord.longitude))
                    }
                }
            }else{
                highlightNorthEast = northEast
                highlightSouthWest = southWest
            }
        }
        if southWest != nil {
            self.boundingMapRect = MKMapRect(southWest: southWest!, northEast: northEast!)
            self.coordinate = southWest!.halfWay(to: northEast!)
        }
        
        if highlightSouthWest == nil {
            self.highlightMapRect = self.boundingMapRect
            self.highlightCoordinate = self.coordinate
        }else{
            self.highlightMapRect = MKMapRect(southWest: highlightSouthWest!, northEast: highlightNorthEast!)
            self.highlightCoordinate = highlightSouthWest!.halfWay(to: highlightNorthEast!)
        }
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
            context.setLineWidth( 5.0 / zoomScale )
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
                        context.setLineWidth( 5.0 / zoomScale )
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
