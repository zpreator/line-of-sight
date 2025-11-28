//
//  TerrainIntersector.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/21/25.
//
//  Computes the first intersection of a ray starting at a distant elevation-based POI
//  (mountain top, ridge, valley) and pointing away from the sun through the POI.
//  Uses cached DEM tiles for terrain lookup.
//
//  Requirements:
//  - POI: lat, lon, elevation (from DEM)
//  - Ray direction: unit vector (dx, dy, dz) in ENU coordinates, pointing away from sun
//  - DEM lookup function: async terrain query
//  - Step size (meters) and maximum distance
//
//  Process:
//  1. Treat POI as origin of local ENU tangent plane
//  2. March along ray in fixed increments from t=0 to maxDistance:
//     - Compute ENU coordinates: x = dx*t, y = dy*t, z = h0 + dz*t
//     - Convert ENU offsets → lat/lon
//     - Lookup DEM height at that location
//     - If DEM_height >= z, return coordinate as intersection
//  3. Binary search refinement for accuracy
//
//  Example usage:
//    let intersector = TerrainIntersector()
//    let sunPos = AstronomicalCalculations.position(for: .sun, at: date, coordinate: mtHood)
//    let sunDirection = CoordinateUtils.azAltToENU(azimuth: sunPos.azimuth, altitude: sunPos.elevation)
//    let rayDirection = -sunDirection  // Away from sun
//    let intersection = await intersector.intersectRay(from: mtHood, poiElevation: 3429, directionENU: rayDirection)
//

import Foundation
import CoreLocation
import simd

/// Performs ray-terrain intersection calculations using ray marching
actor TerrainIntersector {
    
    // MARK: - Properties
    
    private let demService: DEMService
    
    /// Coarse step size for initial ray marching in meters
    private let coarseStepSize: Double = 500.0
    
    /// Binary search tolerance for intersection refinement in meters
    private let binarySearchTolerance: Double = 1.0
    
    // MARK: - Initialization
    
    init(demService: DEMService = DEMService()) {
        self.demService = demService
    }
    
    // MARK: - Public Methods
    
    /// Find where a ray from a POI intersects the terrain
    /// Uses coarse stepping (500m) followed by binary search refinement (1m precision)
    /// - Parameters:
    ///   - poi: Point of interest coordinate
    ///   - poiElevation: Elevation of the POI in meters
    ///   - directionENU: Direction vector in ENU coordinates (should be normalized)
    ///   - maxDistanceMeters: Maximum distance to march along the ray
    /// - Returns: Coordinate where the ray intersects terrain, or nil if no intersection
    func intersectRay(
        from poi: CLLocationCoordinate2D,
        poiElevation: Double,
        directionENU: simd_double3,
        maxDistanceMeters: Double = 30000
    ) async -> CLLocationCoordinate2D? {
        // Normalize the direction vector
        let direction = directionENU.normalized

        // Check if the ray immediately points underground (negative z-component)
        let tolerance: Double = -0.2 // Allow a small tolerance for near-horizontal rays
        if direction.z < tolerance {
            return nil
        }

        // Starting position - start with a minimum offset to avoid intersecting at the POI itself
        let minOffset = 100.0  // Start checking 100m away from POI
        var currentDistance: Double = minOffset

        // Track failed elevation lookups
        var consecutiveFailures = 0
        let maxConsecutiveFailures = 10  // Stop if 10 consecutive elevation lookups fail
        
        // Track the last position that was above terrain for binary search
        var lastAboveDistance: Double? = nil

        // Coarse step along the ray using 500m steps
        while currentDistance < maxDistanceMeters {
            // Calculate current position
            let currentENU = direction * currentDistance
            let currentCoordinate = CoordinateUtils.enuToCoordinate(
                enuOffset: currentENU,
                origin: poi
            )

            // Calculate ray elevation at this position
            let rayElevation = poiElevation + currentENU.z

            // Get terrain elevation at this point
            guard let terrainElevation = await demService.elevation(at: currentCoordinate) else {
                // If we can't get elevation data, continue searching
                consecutiveFailures += 1
                if consecutiveFailures >= maxConsecutiveFailures {
                    // Too many failures, likely out of coverage area
                    return nil
                }
                currentDistance += coarseStepSize
                continue
            }

            // Reset failure counter on successful lookup
            consecutiveFailures = 0

            // Check for intersection (ray elevation <= terrain elevation)
            if rayElevation <= terrainElevation {
                // Found intersection! Use binary search for refinement
                let startDistance = lastAboveDistance ?? max(minOffset, currentDistance - coarseStepSize)
                return await refineIntersection(
                    poi: poi,
                    poiElevation: poiElevation,
                    direction: direction,
                    startDistance: startDistance,
                    endDistance: currentDistance
                )
            }
            
            // Ray is still above terrain, continue
            lastAboveDistance = currentDistance
            currentDistance += coarseStepSize
        }

        // No intersection found within max distance
        return nil
    }
    
    /// Intersect ray with terrain, but going opposite to a celestial object's direction
    /// This finds where a photographer should stand to see the celestial object behind the POI
    /// - Parameters:
    ///   - poi: Point of interest coordinate
    ///   - poiElevation: Elevation of the POI in meters
    ///   - celestialAzimuth: Azimuth of celestial object in degrees
    ///   - celestialAltitude: Altitude of celestial object in degrees
    ///   - maxDistanceMeters: Maximum distance to search
    /// - Returns: Coordinate where photographer should be
    func photographerPosition(
        poi: CLLocationCoordinate2D,
        poiElevation: Double,
        celestialAzimuth: Double,
        celestialAltitude: Double,
        maxDistanceMeters: Double = 30000
    ) async -> CLLocationCoordinate2D? {
        
        // Convert celestial direction to ENU
        let celestialDirection = CoordinateUtils.azAltToENU(
            azimuth: celestialAzimuth,
            altitude: celestialAltitude
        )
        
        // We want to find a position where the line from that position to the POI
        // is in the opposite direction of the celestial object
        // So we march in the opposite direction
        let oppositeDirection = -celestialDirection
        
        // For photographer position, we typically want to be on the ground
        // So we'll march horizontally (altitude = 0) away from POI
        let horizontalDirection = simd_double3(
            oppositeDirection.x,
            oppositeDirection.y,
            0
        ).normalized
        
        // March along this direction until we find a suitable ground position
        var distance: Double = 100.0 // Start at least 100m away
        let maxDistance = min(maxDistanceMeters, 10000.0) // Cap at 10km for photographer
        
        while distance < maxDistance {
            let offset = horizontalDirection * distance
            let photographerCoord = CoordinateUtils.enuToCoordinate(
                enuOffset: offset,
                origin: poi
            )
            
            // Get ground elevation at photographer position
            if let groundElevation = await demService.elevation(at: photographerCoord) {
                // Check if we have line of sight to POI from this position
                let hasLineOfSight = await checkLineOfSight(
                    from: photographerCoord,
                    fromElevation: groundElevation + 1.7, // Eye level (1.7m above ground)
                    to: poi,
                    toElevation: poiElevation
                )
                
                if hasLineOfSight {
                    return photographerCoord
                }
            }
            
            distance += 100.0 // Increment by 100m
        }
        
        // If no suitable position found, return a simple geometric calculation
        // Just go opposite direction at a reasonable distance
        return poi.destination(
            bearing: CoordinateUtils.radiansToDegrees(atan2(oppositeDirection.x, oppositeDirection.y)),
            distance: 1000.0
        )
    }
    
    // MARK: - Private Methods
    
    /// Refine intersection point using binary search to 1m precision
    private func refineIntersection(
        poi: CLLocationCoordinate2D,
        poiElevation: Double,
        direction: simd_double3,
        startDistance: Double,
        endDistance: Double
    ) async -> CLLocationCoordinate2D {
        
        var low = startDistance
        var high = endDistance
        
        // Binary search until we reach 1m precision
        while (high - low) > binarySearchTolerance {
            let mid = (low + high) / 2.0
            let midENU = direction * mid
            let midCoord = CoordinateUtils.enuToCoordinate(enuOffset: midENU, origin: poi)
            
            guard let terrainElev = await demService.elevation(at: midCoord) else {
                // If we can't get elevation, return the high point (conservative)
                break
            }
            
            let rayElev = poiElevation + midENU.z
            
            if rayElev > terrainElev {
                // Ray is above terrain, move forward
                low = mid
            } else {
                // Ray is at or below terrain, move backward
                high = mid
            }
        }
        
        // Return the refined position (use high to be conservative)
        let finalENU = direction * high
        return CoordinateUtils.enuToCoordinate(enuOffset: finalENU, origin: poi)
    }
    
    /// Check if there's an unobstructed line of sight between two points
    private func checkLineOfSight(
        from start: CLLocationCoordinate2D,
        fromElevation: Double,
        to end: CLLocationCoordinate2D,
        toElevation: Double
    ) async -> Bool {
        
        // Calculate number of sample points along the path
        let distance = start.distance(to: end)
        let samples = Int(distance / 50.0) + 1 // Sample every 50 meters
        
        guard samples > 1 else { return true }
        
        // Sample elevations along the path
        var coordinates: [CLLocationCoordinate2D] = []
        for i in 0..<samples {
            let fraction = Double(i) / Double(samples - 1)
            let lat = start.latitude + (end.latitude - start.latitude) * fraction
            let lon = start.longitude + (end.longitude - start.longitude) * fraction
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        
        let elevations = await demService.elevations(at: coordinates)
        
        // Check if line of sight is clear at each point
        for (i, terrainElevation) in elevations.enumerated() {
            guard let terrainElev = terrainElevation else { continue }
            
            let fraction = Double(i) / Double(samples - 1)
            let lineElevation = fromElevation + (toElevation - fromElevation) * fraction
            
            // Add a small buffer (2m) to account for uncertainty
            if terrainElev > lineElevation + 2.0 {
                return false // Terrain blocks the view
            }
        }
        
        return true // Clear line of sight
    }
}

// MARK: - Supporting Types

struct RayIntersection {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double
    let distance: Double
}
