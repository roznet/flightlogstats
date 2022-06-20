//
//  FlightData+Constants.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import Foundation
import OSLog

extension FlightLogFile {
    enum Field : String {
        // the rawValue needs to be the same as in the original csv log file
        case Unknown = "Unknown"
        
        case Lcl_Date = "Lcl Date"
        case Lcl_Time = "Lcl Time"
        case UTCOfst = "UTCOfst"
        
        // From Garmin
        case AtvWpt = "AtvWpt"
        case Latitude = "Latitude"
        case Longitude = "Longitude"
        case AltInd = "AltInd"
        case BaroA = "BaroA"
        case AltMSL = "AltMSL"
        case OAT = "OAT"
        case IAS = "IAS"
        case GndSpd = "GndSpd"
        case VSpd = "VSpd"
        case Pitch = "Pitch"
        case Roll = "Roll"
        case LatAc = "LatAc"
        case NormAc = "NormAc"
        case HDG = "HDG"
        case TRK = "TRK"
        case volt1 = "volt1"
        case volt2 = "volt2"
        case amp1 = "amp1"
        case FQtyL = "FQtyL"
        case FQtyR = "FQtyR"
        case E1_FFlow = "E1 FFlow"
        case E1_OilT = "E1 OilT"
        case E1_OilP = "E1 OilP"
        case E1_MAP = "E1 MAP"
        case E1_RPM = "E1 RPM"
        case E1_PctPwr = "E1 %Pwr"
        case E1_CHT1 = "E1 CHT1"
        case E1_CHT2 = "E1 CHT2"
        case E1_CHT3 = "E1 CHT3"
        case E1_CHT4 = "E1 CHT4"
        case E1_CHT5 = "E1 CHT5"
        case E1_CHT6 = "E1 CHT6"
        case E1_EGT1 = "E1 EGT1"
        case E1_EGT2 = "E1 EGT2"
        case E1_EGT3 = "E1 EGT3"
        case E1_EGT4 = "E1 EGT4"
        case E1_EGT5 = "E1 EGT5"
        case E1_EGT6 = "E1 EGT6"
        case E1_TIT1 = "E1 TIT1"
        case E1_TIT2 = "E1 TIT2"
        case E1_Torq = "E1 Torq"
        case E1_NG = "E1 NG"
        case E1_ITT = "E1 ITT"
        case E2_FFlow = "E2 FFlow"
        case E2_MAP = "E2 MAP"
        case E2_RPM = "E2 RPM"
        case E2_Torq = "E2 Torq"
        case E2_NG = "E2 NG"
        case E2_ITT = "E2 ITT"
        case AltGPS = "AltGPS"
        case TAS = "TAS"
        case HSIS = "HSIS"
        case CRS = "CRS"
        case NAV1 = "NAV1"
        case NAV2 = "NAV2"
        case COM1 = "COM1"
        case COM2 = "COM2"
        case HCDI = "HCDI"
        case VCDI = "VCDI"
        case WndSpd = "WndSpd"
        case WndDr = "WndDr"
        case WptDst = "WptDst"
        case WptBrg = "WptBrg"
        case MagVar = "MagVar"
        case AfcsOn = "AfcsOn"
        case RollM = "RollM"
        case PitchM = "PitchM"
        case RollC = "RollC"
        case PichC = "PichC"
        case VSpdG = "VSpdG"
        case GPSfix = "GPSfix"
        case HAL = "HAL"
        case VAL = "VAL"
        case HPLwas = "HPLwas"
        case HPLfd = "HPLfd"
        case VPLwas = "VPLwas"
        
        // Calculated
        case FQtyT = "FQtyT"
        case Distance = "Distance"
        case WndDirect = "WndDirect"
        case WndCross  = "WndCross"
        
        var displayName : String { return self.rawValue }
        
        //calc
        //distance
        //crosswind, headwind
        //E1CHTMax
        //E1TITMax
        //FQtyT
    }
    
    enum MetaField : String {
        case log_version = "log_version"
        case log_content_version = "log_content_version"
        case Product = "Product"
        case airframe_name = "airframe_name"
        case unit_software_part_number = "unit_software_part_number"
        case unit_software_version = "unit_software_version"
        case system_software_part_number = "system_software_part_number"
        case system_id = "system_id"
        case mode = "mode"
        case flightstream_header = "flightstream_header"
    }
}

extension FlightLogFile.Field {
    struct FieldDef : Codable {
        let field : String
        let order : Int
        let unit : String
        let description : String
        let unit_description : String
        
    }
    static var fieldDefinitions : [FlightLogFile.Field:FieldDef] = {
        var rv : [FlightLogFile.Field:FieldDef] = [:]
        do {
            if let bundlePath = Bundle.main.path(forResource: "logFileFields", ofType: "json"),
               let jsonData = try String(contentsOfFile: bundlePath).data(using: .utf8) {
                let defs = try JSONDecoder().decode([FieldDef].self, from: jsonData)
                for def in defs {
                    if let field = FlightLogFile.Field(rawValue: def.field) {
                        rv[field] = def
                    }else{
                        Logger.app.error("Incompatible field \(def.field)")
                    }
                }
            }
        } catch {
            Logger.app.error( "failed to decode field json \(error.localizedDescription)" )
        }
        return rv
    }()
    
    var localizedDescription : String {
        if let def = Self.fieldDefinitions[self] {
            return def.description
        }
        return self.rawValue
    }
    
    var order : Int {
        if let def = Self.fieldDefinitions[self] {
            return def.order
        }
        return 9999
    }
    
    func format(valueStats : ValueStats, context : DisplayContext = DisplayContext() ) -> String {
        switch self {
        case .AltInd:
            return context.formatStats(altitude: valueStats)
        case .BaroA:
            return context.formatStats(baro: valueStats)
        case .AltMSL:
            return context.formatStats(altitude: valueStats)
        case .OAT:
            return context.formatStats(valueStats)
        case .IAS:
            return context.formatStats(speed: valueStats)
        case .GndSpd:
            return context.formatStats(speed: valueStats)
        case .VSpd:
            return context.formatStats(fpm: valueStats)
        case .Pitch:
            return context.formatStats(valueStats)
        case .Roll:
            return context.formatStats(valueStats)
        case .LatAc:
            return context.formatStats(valueStats)
        case .NormAc:
            return context.formatStats(valueStats)
        case .HDG:
            return context.formatStats(degree: valueStats)
        case .TRK:
            return context.formatStats(degree: valueStats)
        case .volt1:
            return context.formatStats(valueStats)
        case .volt2:
            return context.formatStats(valueStats)
        case .amp1:
            return context.formatStats(valueStats)
        case .FQtyL:
            return context.formatStats(gallon: valueStats)
        case .FQtyR:
            return context.formatStats(gallon: valueStats)
        case .E1_FFlow:
            return context.formatStats(gph: valueStats)
        case .E1_OilT:
            return context.formatStats(valueStats)
        case .E1_OilP:
            return context.formatStats(valueStats)
        case .E1_MAP:
            return context.formatStats(map: valueStats)
        case .E1_RPM:
            return context.formatStats(valueStats)
        case .E1_PctPwr:
            return context.formatStats(percent: valueStats)
        case .E1_CHT1:
            return context.formatStats(engineTemp: valueStats)
        case .E1_CHT2:
            return context.formatStats(engineTemp: valueStats)
        case .E1_CHT3:
            return context.formatStats(engineTemp: valueStats)
        case .E1_CHT4:
            return context.formatStats(engineTemp: valueStats)
        case .E1_CHT5:
            return context.formatStats(engineTemp: valueStats)
        case .E1_CHT6:
            return context.formatStats(engineTemp: valueStats)
        case .E1_EGT1:
            return context.formatStats(engineTemp: valueStats)
        case .E1_EGT2:
            return context.formatStats(engineTemp: valueStats)
        case .E1_EGT3:
            return context.formatStats(engineTemp: valueStats)
        case .E1_EGT4:
            return context.formatStats(engineTemp: valueStats)
        case .E1_EGT5:
            return context.formatStats(engineTemp: valueStats)
        case .E1_EGT6:
            return context.formatStats(engineTemp: valueStats)
        case .E1_TIT1:
            return context.formatStats(engineTemp: valueStats)
        case .E1_TIT2:
            return context.formatStats(engineTemp: valueStats)
        case .E1_Torq:
            return context.formatStats(valueStats)
        case .E1_NG:
            return context.formatStats(valueStats)
        case .E1_ITT:
            return context.formatStats(valueStats)
        case .E2_FFlow:
            return context.formatStats(gph: valueStats)
        case .E2_MAP:
            return context.formatStats(map: valueStats)
        case .E2_RPM:
            return context.formatStats(valueStats)
        case .E2_Torq:
            return context.formatStats(valueStats)
        case .E2_NG:
            return context.formatStats(valueStats)
        case .E2_ITT:
            return context.formatStats(valueStats)
        case .AltGPS:
            return context.formatStats(altitude: valueStats)
        case .TAS:
            return context.formatStats(speed: valueStats)
        case .HSIS:
            return context.formatStats(valueStats)
        case .CRS:
            return context.formatStats(degree: valueStats)
        case .NAV1:
            return context.formatStats(frequency: valueStats)
        case .NAV2:
            return context.formatStats(frequency: valueStats)
        case .COM1:
            return context.formatStats(frequency: valueStats)
        case .COM2:
            return context.formatStats(frequency: valueStats)
        case .HCDI:
            return context.formatStats(valueStats)
        case .VCDI:
            return context.formatStats(valueStats)
        case .WndSpd:
            return context.formatStats(speed: valueStats)
        case .WndDr:
            return context.formatStats(degree: valueStats)
        case .WptDst:
            return context.formatStats(distance: valueStats, total: true)
        case .WptBrg:
            return context.formatStats(degree: valueStats)
        case .MagVar:
            return context.formatStats(degree: valueStats)
        case .AfcsOn:
            return context.formatStats(autopilot: valueStats)
        case .RollM:
            return context.formatStats(valueStats)
        case .PitchM:
            return context.formatStats(valueStats)
        case .RollC:
            return context.formatStats(degree: valueStats)
        case .PichC:
            return context.formatStats(degree: valueStats)
        case .VSpdG:
            return context.formatStats(fpm: valueStats)
        case .GPSfix:
            return context.formatStats(valueStats)
        case .HAL:
            return context.formatStats(valueStats)
        case .VAL:
            return context.formatStats(valueStats)
        case .HPLwas:
            return context.formatStats(valueStats)
        case .HPLfd:
            return context.formatStats(valueStats)
        case .VPLwas:
            return context.formatStats(valueStats)
        case .Unknown:
            return context.formatStats(valueStats)
        case .AtvWpt:
            return context.formatStats(valueStats)
        case .Latitude:
            return context.formatStats(valueStats)
        case .Longitude:
            return context.formatStats(valueStats)
        case .Lcl_Date:
            return ""
        case .Lcl_Time:
            return ""
        
        // Calculated
        case .FQtyT:
            return context.formatStats(gallon: valueStats, used: false)
        case .Distance:
            return context.formatStats(distance: valueStats, total: true)
        case .WndCross:
            return context.formatStats(speed: valueStats)
        case .WndDirect:
            return context.formatStats(speed: valueStats)
        case .UTCOfst:
            return ""
        }
    }
}

extension FlightLogFile.Field : CustomStringConvertible {
    var description: String { return self.rawValue }
}

extension FlightLogFile.MetaField : CustomStringConvertible {
    var description: String { return self.rawValue }
}

