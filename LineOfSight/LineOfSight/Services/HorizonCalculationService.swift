//
//  HorizonCalculationService.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/29/25.
//
//  Calculates horizon rise/set events for celestial objects accounting for terrain elevation.
//  Uses time sampling to detect when an object transitions from obscured to visible (rise)
//  or visible to obscured (set) by terrain.

import Foundation
import CoreLocation

/// Result of a horizon calculation containing all rise/set events for a given day
struct HorizonCalculationResult {
    let observer: Location
    let date: Date
    let celestialObject: CelestialObject
    let events: [HorizonEventDetail]
    
    /// Summary statistics
    var firstRise: HorizonEventDetail? {
        events.first { $0.type == .rise }
    }
    
    var lastSet: HorizonEventDetail? {
        events.reversed().first { $0.type == .set }
    }
    
    var isAlwaysVisible: Bool {
        events.isEmpty && events.allSatisfy { $0.type != .set }
    }
    
    var neverVisible: Bool {
        events.isEmpty
    }
}

/// Detailed information about a specific horizon event
struct HorizonEventDetail: Identifiable {
    let id = UUID()
    let type: HorizonEventType
    let time: Date
    let azimuth: Double  // Direction where event occurs
    let objectAltitude: Double  // Celestial object's altitude at event
    let terrainElevation: Double  // Angular elevation of terrain at that azimuth
    let intersectionPoint: CLLocationCoordinate2D  // Where terrain intersects
    let distance: Double  // Distance to terrain intersection in meters
}

/// Type of horizon event
enum HorizonEventType {
    case rise  // Object becomes visible
    case set   // Object becomes obscured
}

/// Service for calculating horizon rise/set events
actor HorizonCalculationService {
    
    // MARK: - Properties
    
    private let demService: DEMService
    private let terrainIntersector: TerrainIntersector
    
    /// Time interval for initial coarse sampling (5 minutes)
    private let samplingInterval: TimeInterval = 300.0  // 5 minutes = 300 seconds
    
    /// Maximum distance to check for terrain in meters (30km)
    private let maxTerrainDistance: Double = 30_000.0
    
    /// Binary search precision for event time refinement (1 second)
    private let timeRefinementTolerance: TimeInterval = 1.0
    
    // MARK: - Initialization
    
    init(demService: DEMService? = nil, terrainIntersector: TerrainIntersector? = nil) {
        self.demService = demService ?? DEMService()
        self.terrainIntersector = terrainIntersector ?? TerrainIntersector()
    }
    
    // MARK: - Public Methods
    
    /// Calculate all horizon rise/set events for a celestial object on a given day
    /// - Parameters:
    ///   - observer: Observer's location
    ///   - date: Date to calculate for (uses full 24-hour period)
    ///   - object: Celestial object to track
    ///   - progressCallback: Optional callback for progress updates (0.0 to 1.0)
    /// - Returns: Result containing all horizon events
    func calculateHorizonEvents(
        observer: Location,
        date: Date,
        object: CelestialObject,
        progressCallback: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> HorizonCalculationResult {
        
        print("🔵 [HorizonCalc] Starting calculation for \(object.name) at \(observer.name ?? "Unknown")")
        print("🔵 [HorizonCalc] Observer: \(observer.coordinate.latitude), \(observer.coordinate.longitude), elevation: \(observer.elevation)m")
        print("🔵 [HorizonCalc] Date: \(date)")
        
        // Get start and end of day in local timezone
        let calendar = Calendar.current
        guard let startOfDay = calendar.startOfDay(for: date) as Date?,
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            print("❌ [HorizonCalc] Failed to calculate start/end of day")
            throw HorizonCalculationError.invalidDate
        }
        
        print("🔵 [HorizonCalc] Time range: \(startOfDay) to \(endOfDay)")
        
        // Sample the full day at regular intervals
        print("🔵 [HorizonCalc] Starting day sampling with \(samplingInterval)s intervals")
        let samples = await sampleDay(
            observer: observer,
            startTime: startOfDay,
            endTime: endOfDay,
            object: object,
            progressCallback: progressCallback
        )
        
        print("🔵 [HorizonCalc] Collected \(samples.count) samples")
        let visibleCount = samples.filter { $0.isVisible }.count
        print("🔵 [HorizonCalc] Visible samples: \(visibleCount)/\(samples.count)")
        
        // Detect transitions (rise/set events)
        print("🔵 [HorizonCalc] Detecting events from samples")
        let events = await detectEvents(
            samples: samples,
            observer: observer,
            object: object
        )
        
        print("🔵 [HorizonCalc] Found \(events.count) events: \(events.filter { $0.type == .rise }.count) rise, \(events.filter { $0.type == .set }.count) set")
        for event in events {
            print("  📍 \(event.type == .rise ? "🌅 Rise" : "🌇 Set") at \(event.time): az=\(String(format: "%.1f°", event.azimuth)), obj_alt=\(String(format: "%.1f°", event.objectAltitude)), terrain=\(String(format: "%.1f°", event.terrainElevation))")
        }
        
        return HorizonCalculationResult(
            observer: observer,
            date: date,
            celestialObject: object,
            events: events
        )
    }
    
    // MARK: - Private Methods
    
    /// Sample visibility state at regular intervals throughout the day
    private func sampleDay(
        observer: Location,
        startTime: Date,
        endTime: Date,
        object: CelestialObject,
        progressCallback: (@Sendable (Double) async -> Void)?
    ) async -> [VisibilitySample] {
        
        var samples: [VisibilitySample] = []
        var currentTime = startTime
        let totalDuration = endTime.timeIntervalSince(startTime)
        let expectedSamples = Int(totalDuration / samplingInterval)
        print("🔵 [HorizonCalc] Sampling \(expectedSamples) points over \(totalDuration/3600) hours")
        
        while currentTime <= endTime {
            // Calculate celestial object position
            let position = AstronomicalCalculations.position(
                for: object,
                at: currentTime,
                coordinate: observer.coordinate
            )
            
            // Only check terrain if object is near horizon (-5° to +10°)
            // This optimizes performance by skipping terrain checks when object is clearly above/below
            var isVisible = position.elevation > 0
            var terrainElevation: Double? = nil
            
            if position.elevation > -5.0 && position.elevation < 10.0 {
                // Object is near horizon, check terrain
                terrainElevation = await getTerrainElevation(
                    observer: observer,
                    azimuth: position.azimuth
                )
                
                if let terrain = terrainElevation {
                    isVisible = position.elevation > terrain
                    if samples.count % 50 == 0 {  // Log every 50th sample near horizon
                        print("  🔍 Sample \(samples.count): time=\(currentTime), az=\(String(format: "%.1f°", position.azimuth)), obj=\(String(format: "%.1f°", position.elevation)), terrain=\(String(format: "%.1f°", terrain)), visible=\(isVisible)")
                    }
                }
            } else if position.elevation < -5.0 {
                // Object is well below mathematical horizon
                isVisible = false
            }
            
            samples.append(VisibilitySample(
                time: currentTime,
                azimuth: position.azimuth,
                objectAltitude: position.elevation,
                terrainElevation: terrainElevation,
                isVisible: isVisible
            ))
            
            // Report progress
            if let callback = progressCallback {
                let progress = currentTime.timeIntervalSince(startTime) / totalDuration
                await callback(progress)
            }
            
            currentTime = currentTime.addingTimeInterval(samplingInterval)
        }
        
        return samples
    }
    
    /// Detect rise/set events from visibility samples
    private func detectEvents(
        samples: [VisibilitySample],
        observer: Location,
        object: CelestialObject
    ) async -> [HorizonEventDetail] {
        
        var events: [HorizonEventDetail] = []
        
        print("🔵 [HorizonCalc] Scanning \(samples.count) samples for transitions")
        
        // Look for state transitions
        for i in 1..<samples.count {
            let previous = samples[i - 1]
            let current = samples[i]
            
            // Rise event: was not visible, now visible
            if !previous.isVisible && current.isVisible {
                print("  🌅 Detected RISE transition at sample \(i): \(previous.time) to \(current.time)")
                if let event = await refineEvent(
                    type: .rise,
                    startSample: previous,
                    endSample: current,
                    observer: observer,
                    object: object
                ) {
                    events.append(event)
                }
            }
            // Set event: was visible, now not visible
            else if previous.isVisible && !current.isVisible {
                print("  🌇 Detected SET transition at sample \(i): \(previous.time) to \(current.time)")
                if let event = await refineEvent(
                    type: .set,
                    startSample: previous,
                    endSample: current,
                    observer: observer,
                    object: object
                ) {
                    events.append(event)
                }
            }
        }
        
        return events
    }
    
    /// Refine event time using binary search for precision
    private func refineEvent(
        type: HorizonEventType,
        startSample: VisibilitySample,
        endSample: VisibilitySample,
        observer: Location,
        object: CelestialObject
    ) async -> HorizonEventDetail? {
        
        var startTime = startSample.time
        var endTime = endSample.time
        
        // Binary search to find precise transition time
        while endTime.timeIntervalSince(startTime) > timeRefinementTolerance {
            let midTime = Date(timeIntervalSince1970: (startTime.timeIntervalSince1970 + endTime.timeIntervalSince1970) / 2.0)
            
            let position = AstronomicalCalculations.position(
                for: object,
                at: midTime,
                coordinate: observer.coordinate
            )
            
            let terrainElevation = await getTerrainElevation(
                observer: observer,
                azimuth: position.azimuth
            )
            
            let isVisible = position.elevation > (terrainElevation ?? -1.0)
            
            // Narrow down the search interval
            if type == .rise {
                if isVisible {
                    endTime = midTime
                } else {
                    startTime = midTime
                }
            } else { // .set
                if isVisible {
                    startTime = midTime
                } else {
                    endTime = midTime
                }
            }
        }
        
        // Use the refined time
        let eventTime = type == .rise ? endTime : startTime
        let position = AstronomicalCalculations.position(
            for: object,
            at: eventTime,
            coordinate: observer.coordinate
        )
        
        // Get detailed terrain information for the event
        let terrainElevation = await getTerrainElevation(
            observer: observer,
            azimuth: position.azimuth
        )
        
        guard let terrain = terrainElevation else {
            return nil
        }
        
        // Find the actual terrain intersection point
        let intersection = await getTerrainIntersection(
            observer: observer,
            azimuth: position.azimuth,
            altitude: terrain
        )
        
        return HorizonEventDetail(
            type: type,
            time: eventTime,
            azimuth: position.azimuth,
            objectAltitude: position.elevation,
            terrainElevation: terrain,
            intersectionPoint: intersection.coordinate,
            distance: intersection.distance
        )
    }
    
    /// Get terrain elevation angle in a given direction from observer
    /// - Returns: Angular elevation in degrees, or nil if no terrain found
    private func getTerrainElevation(
        observer: Location,
        azimuth: Double
    ) async -> Double? {
        
        // Convert azimuth to direction vector
        // Start with a horizontal ray (altitude = 0)
        let directionENU = CoordinateUtils.azAltToENU(
            azimuth: azimuth,
            altitude: 0.0
        )
        
        // Find terrain intersection
        guard let intersectionCoord = await terrainIntersector.intersectRay(
            from: observer.coordinate,
            poiElevation: observer.elevation,
            directionENU: directionENU,
            maxDistanceMeters: maxTerrainDistance
        ) else {
            // No terrain found, assume flat horizon at 0°
            return 0.0
        }
        
        // Get elevation at intersection point
        guard let intersectionElevation = await demService.elevation(at: intersectionCoord) else {
            return 0.0
        }
        
        // Calculate angular elevation of terrain from observer
        let distance = CoordinateUtils.distance(
            from: observer.coordinate,
            to: intersectionCoord
        )
        
        let elevationDifference = intersectionElevation - observer.elevation
        let angularElevation = atan2(elevationDifference, distance) * 180.0 / .pi
        
        return angularElevation
    }
    
    /// Get detailed terrain intersection information
    private func getTerrainIntersection(
        observer: Location,
        azimuth: Double,
        altitude: Double
    ) async -> (coordinate: CLLocationCoordinate2D, distance: Double) {
        
        let directionENU = CoordinateUtils.azAltToENU(
            azimuth: azimuth,
            altitude: altitude
        )
        
        if let intersectionCoord = await terrainIntersector.intersectRay(
            from: observer.coordinate,
            poiElevation: observer.elevation,
            directionENU: directionENU,
            maxDistanceMeters: maxTerrainDistance
        ) {
            let distance = CoordinateUtils.distance(
                from: observer.coordinate,
                to: intersectionCoord
            )
            return (intersectionCoord, distance)
        }
        
        // Fallback: project point at max distance
        let fallbackDistance = 10_000.0
        let offset = directionENU * fallbackDistance
        let fallbackCoord = CoordinateUtils.enuToCoordinate(
            enuOffset: offset,
            origin: observer.coordinate
        )
        return (fallbackCoord, fallbackDistance)
    }
}

// MARK: - Supporting Types

/// Sample of visibility state at a specific time
private struct VisibilitySample {
    let time: Date
    let azimuth: Double
    let objectAltitude: Double
    let terrainElevation: Double?
    let isVisible: Bool
}

/// Errors that can occur during horizon calculations
enum HorizonCalculationError: Error, LocalizedError {
    case invalidDate
    case noTerrainData
    case calculationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidDate:
            return "Invalid date provided for horizon calculation"
        case .noTerrainData:
            return "Terrain data not available for this location"
        case .calculationFailed:
            return "Horizon calculation failed"
        }
    }
}
