//
//  SunPathService.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/21/25.
//

import Foundation
import CoreLocation
import simd
import SwiftAA

/// Service for computing sun-terrain alignment paths
actor SunPathService {
    
    // MARK: - Properties
    
    private let demService: DEMService
    private let terrainIntersector: TerrainIntersector
    
    // MARK: - Initialization
    
    init(demService: DEMService = DEMService(), terrainIntersector: TerrainIntersector? = nil) {
        self.demService = demService
        self.terrainIntersector = terrainIntersector ?? TerrainIntersector(demService: demService)
    }
    
    // MARK: - Public Methods
    
    /// Compute sun alignment path for a POI over a full day
    /// Returns coordinates where the sun-POI line intersects terrain for each hour
    /// - Parameters:
    ///   - poi: Point of interest coordinate
    ///   - date: Target date for calculations
    /// - Returns: Array of terrain intersection coordinates (one per hour, 0-23)
    func computeSunAlignmentPath(
        poi: CLLocationCoordinate2D,
        date: Date
    ) async -> [SunAlignmentPoint] {
        
        // Get POI elevation
        guard let poiElevation = await demService.elevation(at: poi) else {
            return []
        }
        
        // Preload tiles around POI for faster queries
        await demService.preloadArea(around: poi, radiusKm: 30.0)
        
        var alignmentPoints: [SunAlignmentPoint] = []
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        // Calculate for each hour of the day
        for hour in 0..<24 {
            let hourDate = startOfDay.addingTimeInterval(TimeInterval(hour * 3600))
            
            // Get sun position
            let sunPosition = AstronomicalCalculations.position(
                for: .sun,
                at: hourDate,
                coordinate: poi
            )
            
            // Skip if sun is below horizon
            guard sunPosition.elevation > 0 else {
                continue
            }
            
            // Convert sun direction to ENU unit vector
            // The sun's direction is where it is, we want the opposite direction (shadow direction)
            let sunDirectionENU = CoordinateUtils.azAltToENU(
                azimuth: sunPosition.azimuth,
                altitude: sunPosition.elevation
            )
            
            // The ray goes from POI in the opposite direction of the sun (shadow direction)
            let rayDirection = -sunDirectionENU
            
            // Find where this ray intersects the terrain
            if let intersection = await terrainIntersector.intersectRay(
                from: poi,
                poiElevation: poiElevation,
                directionENU: rayDirection,
                maxDistanceMeters: 30000
            ) {
                let alignmentPoint = SunAlignmentPoint(
                    time: hourDate,
                    sunAzimuth: sunPosition.azimuth,
                    sunAltitude: sunPosition.elevation,
                    intersectionCoordinate: intersection,
                    poiCoordinate: poi,
                    poiElevation: poiElevation
                )
                alignmentPoints.append(alignmentPoint)
            }
        }
        
        return alignmentPoints
    }
    
    /// Compute optimal photographer positions for sun-POI alignment at specific times
    /// - Parameters:
    ///   - poi: Point of interest coordinate
    ///   - date: Target date
    ///   - hours: Specific hours to calculate (0-23), or nil for all hours
    /// - Returns: Array of photographer positions
    func computePhotographerPositions(
        poi: CLLocationCoordinate2D,
        date: Date,
        hours: [Int]? = nil
    ) async -> [PhotographerPosition] {
        
        // Get POI elevation
        guard let poiElevation = await demService.elevation(at: poi) else {
            return []
        }
        
        // Preload tiles
        await demService.preloadArea(around: poi, radiusKm: 15.0)
        
        var positions: [PhotographerPosition] = []
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let hoursToCalculate = hours ?? Array(0..<24)
        
        for hour in hoursToCalculate {
            let hourDate = startOfDay.addingTimeInterval(TimeInterval(hour * 3600))
            
            // Get sun position
            let sunPosition = AstronomicalCalculations.position(
                for: .sun,
                at: hourDate,
                coordinate: poi
            )
            
            // Skip if sun is below horizon
            guard sunPosition.elevation > 0 else {
                continue
            }
            
            // Find photographer position
            if let photographerCoord = await terrainIntersector.photographerPosition(
                poi: poi,
                poiElevation: poiElevation,
                celestialAzimuth: sunPosition.azimuth,
                celestialAltitude: sunPosition.elevation,
                maxDistanceMeters: 10000
            ) {
                
                // Get photographer elevation
                let photographerElevation = await demService.elevation(at: photographerCoord) ?? 0
                
                let position = PhotographerPosition(
                    time: hourDate,
                    coordinate: photographerCoord,
                    elevation: photographerElevation,
                    sunAzimuth: sunPosition.azimuth,
                    sunAltitude: sunPosition.elevation,
                    distanceToPOI: photographerCoord.distance(to: poi),
                    bearingToPOI: photographerCoord.bearing(to: poi)
                )
                positions.append(position)
            }
        }
        
        return positions
    }
    
    /// Find the best time of day for sun alignment with a POI
    /// Returns the hour when the sun is at the optimal position
    /// - Parameters:
    ///   - poi: Point of interest coordinate
    ///   - date: Target date
    ///   - preferredAzimuth: Preferred sun azimuth (optional)
    /// - Returns: The best alignment time and details
    func findBestAlignmentTime(
        poi: CLLocationCoordinate2D,
        date: Date,
        preferredAzimuth: Double? = nil
    ) async -> SunAlignmentPoint? {
        
        let alignmentPoints = await computeSunAlignmentPath(poi: poi, date: date)
        
        guard !alignmentPoints.isEmpty else { return nil }
        
        // If preferred azimuth is specified, find closest match
        if let targetAzimuth = preferredAzimuth {
            return alignmentPoints.min { point1, point2 in
                let diff1 = abs(point1.sunAzimuth - targetAzimuth)
                let diff2 = abs(point2.sunAzimuth - targetAzimuth)
                return diff1 < diff2
            }
        }
        
        // Otherwise, return the point with highest sun altitude (best lighting)
        return alignmentPoints.max { $0.sunAltitude < $1.sunAltitude }
    }
    
    /// Calculate elevation profile along the sun-POI alignment line
    /// - Parameters:
    ///   - poi: Point of interest
    ///   - alignmentPoint: A specific alignment point
    ///   - samples: Number of elevation samples
    /// - Returns: Elevation profile data
    func elevationProfile(
        poi: CLLocationCoordinate2D,
        alignmentPoint: SunAlignmentPoint,
        samples: Int = 100
    ) async -> [ElevationSample] {
        
        let start = alignmentPoint.intersectionCoordinate
        let end = poi
        
        var profileSamples: [ElevationSample] = []
        let distance = start.distance(to: end)
        
        for i in 0..<samples {
            let fraction = Double(i) / Double(samples - 1)
            let lat = start.latitude + (end.latitude - start.latitude) * fraction
            let lon = start.longitude + (end.longitude - start.longitude) * fraction
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            
            if let elevation = await demService.elevation(at: coord) {
                let sample = ElevationSample(
                    coordinate: coord,
                    elevation: elevation,
                    distanceFromStart: distance * fraction
                )
                profileSamples.append(sample)
            }
        }
        
        return profileSamples
    }
}

// MARK: - Supporting Types

/// Represents a point where the sun-POI line intersects terrain
struct SunAlignmentPoint: Identifiable {
    let id = UUID()
    let time: Date
    let sunAzimuth: Double
    let sunAltitude: Double
    let intersectionCoordinate: CLLocationCoordinate2D
    let poiCoordinate: CLLocationCoordinate2D
    let poiElevation: Double
    
    /// Distance from POI to intersection point
    var distance: Double {
        poiCoordinate.distance(to: intersectionCoordinate)
    }
}

/// Represents an optimal photographer position for sun-POI alignment
struct PhotographerPosition: Identifiable {
    let id = UUID()
    let time: Date
    let coordinate: CLLocationCoordinate2D
    let elevation: Double
    let sunAzimuth: Double
    let sunAltitude: Double
    let distanceToPOI: Double
    let bearingToPOI: Double
}

/// Represents an elevation sample along a path
struct ElevationSample: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let elevation: Double
    let distanceFromStart: Double
}
