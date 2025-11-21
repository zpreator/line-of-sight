//
//  CoordinateUtils.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/21/25.
//

import Foundation
import CoreLocation
import simd

/// Utility functions for coordinate conversions and transformations
struct CoordinateUtils {
    
    // MARK: - Constants
    
    /// Earth's mean radius in meters
    static let earthRadius: Double = 6371000.0
    
    /// Degrees to radians conversion factor
    static let deg2rad = Double.pi / 180.0
    
    /// Radians to degrees conversion factor
    static let rad2deg = 180.0 / Double.pi
    
    // MARK: - Angle Conversions
    
    /// Convert degrees to radians
    static func degreesToRadians(_ degrees: Double) -> Double {
        return degrees * deg2rad
    }
    
    /// Convert radians to degrees
    static func radiansToDegrees(_ radians: Double) -> Double {
        return radians * rad2deg
    }
    
    // MARK: - Distance Calculations
    
    /// Calculate great circle distance between two coordinates using Haversine formula
    /// - Parameters:
    ///   - from: Starting coordinate
    ///   - to: Ending coordinate
    /// - Returns: Distance in meters
    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = degreesToRadians(from.latitude)
        let lon1 = degreesToRadians(from.longitude)
        let lat2 = degreesToRadians(to.latitude)
        let lon2 = degreesToRadians(to.longitude)
        
        let dLat = lat2 - lat1
        let dLon = lon2 - lon1
        
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
    
    /// Calculate initial bearing (azimuth) from one coordinate to another
    /// - Parameters:
    ///   - from: Starting coordinate
    ///   - to: Ending coordinate
    /// - Returns: Bearing in degrees (0° = North, 90° = East)
    static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = degreesToRadians(from.latitude)
        let lon1 = degreesToRadians(from.longitude)
        let lat2 = degreesToRadians(to.latitude)
        let lon2 = degreesToRadians(to.longitude)
        
        let dLon = lon2 - lon1
        
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x)
        
        return fmod(radiansToDegrees(bearing) + 360, 360)
    }
    
    /// Calculate destination coordinate given start, bearing, and distance
    /// - Parameters:
    ///   - start: Starting coordinate
    ///   - bearing: Bearing in degrees
    ///   - distance: Distance in meters
    /// - Returns: Destination coordinate
    static func destination(from start: CLLocationCoordinate2D, bearing: Double, distance: Double) -> CLLocationCoordinate2D {
        let lat1 = degreesToRadians(start.latitude)
        let lon1 = degreesToRadians(start.longitude)
        let brng = degreesToRadians(bearing)
        let angularDistance = distance / earthRadius
        
        let lat2 = asin(sin(lat1) * cos(angularDistance) +
                       cos(lat1) * sin(angularDistance) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(angularDistance) * cos(lat1),
                               cos(angularDistance) - sin(lat1) * sin(lat2))
        
        return CLLocationCoordinate2D(
            latitude: radiansToDegrees(lat2),
            longitude: radiansToDegrees(lon2)
        )
    }
    
    // MARK: - ENU (East-North-Up) Coordinate System
    
    /// Convert a direction (azimuth, altitude) to an ENU (East-North-Up) unit vector
    /// - Parameters:
    ///   - azimuth: Azimuth in degrees (0° = North, 90° = East)
    ///   - altitude: Altitude in degrees (0° = horizon, 90° = zenith)
    /// - Returns: ENU unit vector
    static func azAltToENU(azimuth: Double, altitude: Double) -> simd_double3 {
        let azRad = degreesToRadians(azimuth)
        let altRad = degreesToRadians(altitude)
        
        let cosAlt = cos(altRad)
        
        // ENU coordinate system:
        // East = x, North = y, Up = z
        let east = sin(azRad) * cosAlt
        let north = cos(azRad) * cosAlt
        let up = sin(altRad)
        
        return simd_double3(east, north, up)
    }
    
    /// Convert ENU unit vector to azimuth and altitude
    /// - Parameter enu: ENU unit vector
    /// - Returns: Tuple of (azimuth in degrees, altitude in degrees)
    static func enuToAzAlt(enu: simd_double3) -> (azimuth: Double, altitude: Double) {
        let east = enu.x
        let north = enu.y
        let up = enu.z
        
        let altitude = radiansToDegrees(asin(up))
        let azimuth = fmod(radiansToDegrees(atan2(east, north)) + 360, 360)
        
        return (azimuth, altitude)
    }
    
    /// Convert ENU offset (in meters) to a lat/lon coordinate relative to an origin
    /// - Parameters:
    ///   - enuOffset: Offset in ENU coordinates (meters)
    ///   - origin: Origin coordinate
    /// - Returns: Resulting coordinate
    static func enuToCoordinate(enuOffset: simd_double3, origin: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let east = enuOffset.x
        let north = enuOffset.y
        
        // Calculate bearing and distance
        let distance = sqrt(east * east + north * north)
        let bearing = radiansToDegrees(atan2(east, north))
        
        // Use destination function
        return destination(from: origin, bearing: bearing, distance: distance)
    }
    
    /// Convert a coordinate to ENU offset relative to an origin
    /// - Parameters:
    ///   - coordinate: The coordinate to convert
    ///   - origin: Origin coordinate
    ///   - elevationDiff: Elevation difference in meters (coordinate elevation - origin elevation)
    /// - Returns: ENU offset vector in meters
    static func coordinateToENU(coordinate: CLLocationCoordinate2D, origin: CLLocationCoordinate2D, elevationDiff: Double = 0) -> simd_double3 {
        let dist = distance(from: origin, to: coordinate)
        let brng = bearing(from: origin, to: coordinate)
        
        let brngRad = degreesToRadians(brng)
        let east = dist * sin(brngRad)
        let north = dist * cos(brngRad)
        
        return simd_double3(east, north, elevationDiff)
    }
    
    // MARK: - Interpolation
    
    /// Bilinear interpolation for values at four corners
    /// - Parameters:
    ///   - v00: Value at (0, 0)
    ///   - v10: Value at (1, 0)
    ///   - v01: Value at (0, 1)
    ///   - v11: Value at (1, 1)
    ///   - fx: Fractional x position [0, 1]
    ///   - fy: Fractional y position [0, 1]
    /// - Returns: Interpolated value
    static func bilinearInterpolate(v00: Double, v10: Double, v01: Double, v11: Double, fx: Double, fy: Double) -> Double {
        let v0 = v00 * (1 - fx) + v10 * fx
        let v1 = v01 * (1 - fx) + v11 * fx
        return v0 * (1 - fy) + v1 * fy
    }
}

// MARK: - Extensions

extension CLLocationCoordinate2D {
    /// Calculate distance to another coordinate
    func distance(to other: CLLocationCoordinate2D) -> Double {
        return CoordinateUtils.distance(from: self, to: other)
    }
    
    /// Calculate bearing to another coordinate
    func bearing(to other: CLLocationCoordinate2D) -> Double {
        return CoordinateUtils.bearing(from: self, to: other)
    }
    
    /// Calculate destination coordinate given bearing and distance
    func destination(bearing: Double, distance: Double) -> CLLocationCoordinate2D {
        return CoordinateUtils.destination(from: self, bearing: bearing, distance: distance)
    }
}

extension simd_double3 {
    /// Normalize the vector to unit length
    var normalized: simd_double3 {
        let len = simd.length(self)
        return len > 0 ? self / len : self
    }
    
    /// Get the length of the vector
    var length: Double {
        return simd.length(self)
    }
}
