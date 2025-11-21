//
//  TerrainIntersectionExample.swift
//  LineOfSight
//
//  Example demonstrating terrain intersection calculations
//

import Foundation
import CoreLocation
import simd

/// Example usage of the TerrainIntersector module
struct TerrainIntersectionExample {
    
    /// Example: Find terrain intersection from Mount Hood summit at sunrise
    static func mountHoodSunriseExample() async {
        // Input: Mount Hood summit coordinates
        let mtHoodSummit = CLLocationCoordinate2D(
            latitude: 45.3736,
            longitude: -121.6960
        )
        
        // Get summit elevation from DEM
        let demService = DEMService.shared
        guard let summitElevation = await demService.elevation(at: mtHoodSummit) else {
            print("❌ Could not get summit elevation")
            return
        }
        
        print("🏔️ Mount Hood Summit")
        print("   Location: \(mtHoodSummit.latitude)°, \(mtHoodSummit.longitude)°")
        print("   Elevation: \(summitElevation)m")
        
        // Calculate sun position at 6:00 AM on winter solstice (low sun angle)
        var dateComponents = DateComponents()
        dateComponents.year = 2024
        dateComponents.month = 12
        dateComponents.day = 21
        dateComponents.hour = 6
        dateComponents.minute = 0
        dateComponents.timeZone = TimeZone(identifier: "America/Los_Angeles")
        
        guard let date = Calendar.current.date(from: dateComponents) else {
            print("❌ Could not create date")
            return
        }
        
        // Get sun position
        let sunPosition = AstronomicalCalculations.position(
            for: .sun,
            at: date,
            coordinate: mtHoodSummit
        )
        
        print("\n☀️ Sun Position at 6:00 AM PST")
        print("   Azimuth: \(sunPosition.azimuth)°")
        print("   Altitude: \(sunPosition.elevation)°")
        
        // Convert sun direction to ENU unit vector
        let sunDirectionENU = CoordinateUtils.azAltToENU(
            azimuth: sunPosition.azimuth,
            altitude: sunPosition.elevation
        )
        
        // Ray points AWAY from sun through POI
        let rayDirection = -sunDirectionENU
        
        print("\n📐 Ray Direction (ENU, away from sun)")
        print("   dx: \(rayDirection.x)")
        print("   dy: \(rayDirection.y)")
        print("   dz: \(rayDirection.z)")
        
        // Perform ray-terrain intersection with 10m step size
        let intersector = TerrainIntersector()
        let startTime = Date()
        
        if let intersection = await intersector.intersectRay(
            from: mtHoodSummit,
            poiElevation: summitElevation,
            directionENU: rayDirection,
            stepSize: 10.0,
            maxDistance: 50_000.0  // 50 km
        ) {
            let elapsed = Date().timeIntervalSince(startTime)
            
            print("\n✅ Intersection Found!")
            print("   Location: \(intersection.coordinate.latitude)°, \(intersection.coordinate.longitude)°")
            print("   Elevation: \(intersection.elevation)m")
            print("   Distance from summit: \(String(format: "%.0f", intersection.distance))m")
            print("   Computation time: \(String(format: "%.3f", elapsed))s")
            
            // Calculate geographic properties
            let bearing = CoordinateUtils.bearing(
                from: mtHoodSummit,
                to: intersection.coordinate
            )
            print("   Bearing from summit: \(String(format: "%.1f", bearing))°")
            
        } else {
            print("\n❌ No intersection found within 50km")
        }
    }
    
    /// Example: Photographer position calculations
    static func photographerPositionExample() async {
        // POI: Mount Jefferson (visible from Portland area)
        let mtJefferson = CLLocationCoordinate2D(
            latitude: 44.6742,
            longitude: -121.7992
        )
        
        let demService = DEMService.shared
        guard let elevation = await demService.elevation(at: mtJefferson) else {
            print("❌ Could not get elevation")
            return
        }
        
        print("🏔️ Mount Jefferson")
        print("   Elevation: \(elevation)m")
        
        // Find where to stand to photograph sunrise alignment
        var dateComponents = DateComponents()
        dateComponents.year = 2024
        dateComponents.month = 6
        dateComponents.day = 21  // Summer solstice
        dateComponents.hour = 5
        dateComponents.minute = 30
        dateComponents.timeZone = TimeZone(identifier: "America/Los_Angeles")
        
        guard let date = Calendar.current.date(from: dateComponents) else {
            print("❌ Could not create date")
            return
        }
        
        let sunPosition = AstronomicalCalculations.position(
            for: .sun,
            at: date,
            coordinate: mtJefferson
        )
        
        print("\n☀️ Sun at 5:30 AM PDT")
        print("   Azimuth: \(sunPosition.azimuth)°")
        print("   Altitude: \(sunPosition.elevation)°")
        
        // Ray direction: away from sun
        let sunDirectionENU = CoordinateUtils.azAltToENU(
            azimuth: sunPosition.azimuth,
            altitude: sunPosition.elevation
        )
        let rayDirection = -sunDirectionENU
        
        // Find intersection (photographer location)
        let intersector = TerrainIntersector()
        if let position = await intersector.intersectRay(
            from: mtJefferson,
            poiElevation: elevation,
            directionENU: rayDirection,
            stepSize: 15.0,
            maxDistance: 100_000.0  // 100 km
        ) {
            print("\n📷 Photographer Position")
            print("   Location: \(position.coordinate.latitude)°, \(position.coordinate.longitude)°")
            print("   Elevation: \(position.elevation)m")
            print("   Distance from peak: \(String(format: "%.1f", position.distance / 1000))km")
            
            // Reverse bearing (looking back at mountain)
            let bearing = CoordinateUtils.bearing(
                from: position.coordinate,
                to: mtJefferson
            )
            print("   View direction: \(String(format: "%.1f", bearing))° (toward peak)")
            
        } else {
            print("\n❌ No suitable photographer position found")
        }
    }
    
    /// Example: Compare different step sizes
    static func stepSizeComparisonExample() async {
        let poi = CLLocationCoordinate2D(latitude: 45.5, longitude: -121.5)
        let elevation = 2000.0
        let rayDirection = simd_double3(0.7, 0.7, -0.1)
        let normalized = simd.normalize(rayDirection)
        
        let intersector = TerrainIntersector()
        let stepSizes = [5.0, 10.0, 20.0, 50.0]
        
        print("📊 Step Size Comparison\n")
        
        for stepSize in stepSizes {
            let startTime = Date()
            let result = await intersector.intersectRay(
                from: poi,
                poiElevation: elevation,
                directionENU: normalized,
                stepSize: stepSize,
                maxDistance: 10_000.0
            )
            let elapsed = Date().timeIntervalSince(startTime)
            
            if let intersection = result {
                print("Step: \(Int(stepSize))m → Distance: \(String(format: "%.0f", intersection.distance))m, Time: \(String(format: "%.3f", elapsed))s")
            } else {
                print("Step: \(Int(stepSize))m → No intersection, Time: \(String(format: "%.3f", elapsed))s")
            }
        }
    }
}

// MARK: - Usage in View Model

extension TerrainIntersectionExample {
    
    /// Example integration with FindViewModel
    static func viewModelIntegrationExample() {
        /*
         In your FindViewModel:
         
         @Published var intersectionPoint: CLLocationCoordinate2D?
         @Published var photographerDistance: Double?
         
         func calculateIntersection() async {
             guard let poi = selectedLocation,
                   let poiElevation = selectedElevation else { return }
             
             // Get sun position
             let sunPosition = AstronomicalCalculations.position(
                 for: .sun,
                 at: selectedDate,
                 coordinate: poi
             )
             
             // Ray away from sun
             let sunDirectionENU = CoordinateUtils.azAltToENU(
                 azimuth: sunPosition.azimuth,
                 altitude: sunPosition.elevation
             )
             let rayDirection = -sunDirectionENU
             
             // Find intersection
             let intersector = TerrainIntersector()
             if let result = await intersector.intersectRay(
                 from: poi,
                 poiElevation: poiElevation,
                 directionENU: rayDirection
             ) {
                 await MainActor.run {
                     intersectionPoint = result.coordinate
                     photographerDistance = result.distance
                 }
             }
         }
         */
    }
}
