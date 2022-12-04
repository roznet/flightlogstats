//
//  FlightData+Constants.swift
//  FlightLog1000
//
//  Created by Brice Rosenzweig on 24/04/2022.
//

import Foundation
import OSLog
import RZUtils
import RZData


extension FlightLogFile {
    typealias CategoricalValue = String
    
    public enum Field : String {
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
        case FTotalizerT = "FTotalizerT"
        case E1_EGT_MaxIdx = "E1 EGTMaxIdx"
        case E1_EGT_Max = "E1 EGTMax"
        case E1_EGT_Min = "E1 EGTMin"

        case E1_CHT_MaxIdx = "E1 CHTMaxIdx"
        case E1_CHT_Max = "E1 CHTMax"
        case E1_CHT_Min = "E1 CHTMin"

        case Coordinate = "Coordinate"
        
        // calculated strings
        case FltPhase = "FltPhase"
        
        var displayName : String { return self.rawValue }
        
        //calc
        //distance
        //crosswind, headwind
        //E1CHTMax
        //E1TITMax
        //FQtyT
        
        enum ValueType : String {
            case value, categorical
        }
        
        struct FieldDef : Codable {
            let field : String
            let order : Int
            let unit_key : String
            let description : String
            let unit_description : String
            let type : String

            lazy var unit : GCUnit = { return GCUnit.from(logFileUnit: self.unit_key) }()
            
            private enum CodingKeys : String, CodingKey {
                case field, order, unit_key = "unit", description, unit_description, type
            }
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
        
        static func unit(for field: Field) -> GCUnit {
            if var def = Self.fieldDefinitions[field] {
                return def.unit
            }
            return GCUnit.dimensionless()

        }
        
        var valueType : ValueType {
            if let def = Self.fieldDefinitions[self] {
                return ValueType(rawValue:def.type) ?? .value
            }
            return .value
        }
        
        var localizedDescription : String {
            if let def = Self.fieldDefinitions[self] {
                return def.description
            }
            return self.rawValue
        }
        
        var unit : GCUnit {
            if var def = Self.fieldDefinitions[self] {
                return def.unit
            }
            return GCUnit.dimensionless()
        }
        
        var order : Int {
            if let def = Self.fieldDefinitions[self] {
                return def.order
            }
            return 9999
        }
        
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

extension FlightLogFile.Field : CustomStringConvertible {
    public var description: String { return self.rawValue }
}

extension FlightLogFile.MetaField : CustomStringConvertible {
    var description: String { return self.rawValue }
}

