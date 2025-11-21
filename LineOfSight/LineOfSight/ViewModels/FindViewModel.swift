//
//  FindViewModel.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import Foundation
import CoreLocation
import Combine
import MapKit

/// ViewModel for the Find functionality
@MainActor
class FindViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var selectedLocation: Location?
    @Published var currentUserLocation: CLLocation?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to San Francisco
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @Published var selectedCelestialObject: CelestialObject = .sun
    @Published var targetDate = Date()
    @Published var hourlyIntersections: [HourlyIntersection] = []
    
    // MARK: - Private Properties
    private let locationService: LocationService
    private let demService = DEMService()
    private let sunPathService = SunPathService()
    private let terrainIntersector = TerrainIntersector()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(locationService: LocationService? = nil) {
        self.locationService = locationService ?? LocationService()
        setupLocationObserver()
        requestLocationPermission()
    }
    
    // MARK: - Public Methods
    
    /// Request location permission and start location updates
    func requestLocationPermission() {
        locationService.requestLocationPermission()
        locationService.startLocationUpdates()
    }
    
    /// Handle map tap to select a location
    func selectLocation(at coordinate: CLLocationCoordinate2D, name: String? = nil) {
        isLoading = true
        errorMessage = nil
        
        Task {
            // Get elevation from DEM service (terrain-aware)
            // This will download DEM tiles if not cached
            let elevation = await demService.elevation(at: coordinate)
            
            let location = Location(
                name: name,
                coordinate: coordinate,
                elevation: elevation ?? 0,
                source: .map,
                precision: .approximate
            )
            
            await MainActor.run {
                self.selectedLocation = location
                self.isLoading = false
                
                // Show message if elevation data wasn't available
                if elevation == nil {
                    self.errorMessage = "Elevation data unavailable for this location. Downloading terrain data..."
                }
            }
        }
    }
    
    /// Clear the currently selected location
    func clearSelectedLocation() {
        selectedLocation = nil
        errorMessage = nil
    }
    
    /// Center map on user's current location
    func centerOnUserLocation() {
        // First try to use the cached location
        if let userLocation = currentUserLocation {
            mapRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            return
        }
        
        // If no cached location, try to get it from the location service directly
        if let serviceLocation = locationService.currentLocation {
            currentUserLocation = serviceLocation
            mapRegion = MKCoordinateRegion(
                center: serviceLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            return
        }
        
        // If still no location, start location updates and show error
        locationService.startLocationUpdates()
        errorMessage = "Getting your location..."
    }
    
    /// Calculate alignment for the selected location and celestial object
    func calculateAlignment(name: String = "") -> AlignmentCalculation? {
        guard let location = selectedLocation else { return nil }
        
        let calculationName = name.isEmpty ? "Find \(DateFormatter.shortDate.string(from: targetDate))" : name
        
        // Create alignment calculation with current parameters
        let calculation = AlignmentCalculation(
            id: UUID(),
            name: calculationName,
            landmark: location,
            celestialObject: selectedCelestialObject,
            calculationDate: Date(),
            targetDate: targetDate,
            alignmentEvents: calculateAlignmentEvents(),
            projectionPoints: calculateProjectionPoints()
        )
        
        return calculation
    }
    
    /// Calculate terrain-aware sun alignment path
    func calculateTerrainAlignment() async -> [SunAlignmentPoint] {
        guard let location = selectedLocation,
              selectedCelestialObject.type == .sun else { return [] }
        
        isLoading = true
        errorMessage = nil
        
        let alignmentPoints = await sunPathService.computeSunAlignmentPath(
            poi: location.coordinate,
            date: targetDate
        )
        
        await MainActor.run {
            self.isLoading = false
        }
        
        return alignmentPoints
    }
    
    /// Calculate optimal photographer positions for the current selection
    func calculatePhotographerPositions(hours: [Int]? = nil) async -> [PhotographerPosition] {
        guard let location = selectedLocation,
              selectedCelestialObject.type == .sun else { return [] }
        
        isLoading = true
        errorMessage = nil
        
        let positions = await sunPathService.computePhotographerPositions(
            poi: location.coordinate,
            date: targetDate,
            hours: hours
        )
        
        await MainActor.run {
            self.isLoading = false
        }
        
        return positions
    }
    
    /// Calculate hourly ray-terrain intersections for all 24 hours
    func calculateHourlyIntersections() async {
        guard let location = selectedLocation else { return }
        
        isLoading = true
        errorMessage = nil
        
        print("\n🔵 ====== Starting Hourly Intersection Calculation ======")
        print("🔵 POI: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        print("🔵 Elevation: \(location.elevation)m")
        print("🔵 Date: \(targetDate)")
        
        var intersections: [HourlyIntersection] = []
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: targetDate)
        
        // Calculate for each hour of the day
        for hour in 0..<24 {
            print("\n⏰ === Hour \(hour)/24 ===")
            
            let eventDate = startDate.addingTimeInterval(TimeInterval(hour * 3600))
            
            // Get sun position at this hour
            let sunPosition = AstronomicalCalculations.position(
                for: selectedCelestialObject,
                at: eventDate,
                coordinate: location.coordinate
            )
            
            print("☀️ Sun position - Azimuth: \(String(format: "%.1f", sunPosition.azimuth))°, Elevation: \(String(format: "%.1f", sunPosition.elevation))°")
            
            // Only calculate if sun is above horizon with minimum elevation
            // Skip very low sun angles as they result in nearly horizontal rays
            // that may not intersect terrain within reasonable distance
            let minimumSunElevation = 2.0  // degrees
            if sunPosition.elevation > minimumSunElevation {
                print("✅ Sun above \(minimumSunElevation)° elevation, calculating intersection...")
                
                // Convert sun direction to ENU
                let sunDirectionENU = CoordinateUtils.azAltToENU(
                    azimuth: sunPosition.azimuth,
                    altitude: sunPosition.elevation
                )
                
                // We want to find where a photographer should stand to see the sun behind the POI
                // This means casting a ray FROM the sun, THROUGH the POI, to the ground
                // The sun direction vector points TOWARD the sun
                // We need the opposite - the direction a ray from the sun would travel
                // So we negate it to get the direction from sun through POI
                let rayDirection = -sunDirectionENU
                
                print("📐 Ray direction (ENU): (\(String(format: "%.3f", rayDirection.x)), \(String(format: "%.3f", rayDirection.y)), \(String(format: "%.3f", rayDirection.z)))")
                print("🔍 Sun is at elevation \(String(format: "%.1f", sunPosition.elevation))°, ray should descend (negative Z)")
                
                // Adjust max distance based on sun elevation
                // Lower sun = more horizontal ray = need to search closer
                let maxDistance: Double
                if sunPosition.elevation < 5 {
                    maxDistance = 10_000.0  // 10km for very low sun
                } else if sunPosition.elevation < 10 {
                    maxDistance = 25_000.0  // 25km for low sun
                } else {
                    maxDistance = 50_000.0  // 50km for higher sun
                }
                
                print("🎯 Max search distance: \(String(format: "%.0f", maxDistance/1000))km")
                
                // Find intersection
                if let intersectionCoord = await terrainIntersector.intersectRay(
                    from: location.coordinate,
                    poiElevation: location.elevation,
                    directionENU: rayDirection,
                    maxDistanceMeters: maxDistance
                ) {
                    let distance = location.coordinate.distance(to: intersectionCoord)
                    
                    print("✅ Found intersection at \(intersectionCoord.latitude), \(intersectionCoord.longitude)")
                    print("📏 Distance: \(String(format: "%.0f", distance))m")
                    
                    intersections.append(HourlyIntersection(
                        hour: hour,
                        time: eventDate,
                        coordinate: intersectionCoord,
                        sunAzimuth: sunPosition.azimuth,
                        sunElevation: sunPosition.elevation,
                        distance: distance
                    ))
                } else {
                    print("❌ No intersection found within \(String(format: "%.0f", maxDistance/1000))km")
                }
            } else if sunPosition.elevation > 0 {
                print("⚠️ Sun too low (\(String(format: "%.1f", sunPosition.elevation))°), skipping...")
            } else {
                print("⬇️ Sun below horizon, skipping...")
            }
        }
        
        print("\n🔵 ====== Calculation Complete ======")
        print("🔵 Found \(intersections.count) intersections out of 24 hours\n")
        
        await MainActor.run {
            self.hourlyIntersections = intersections
            self.isLoading = false
        }
    }
    
    /// Find the best alignment time for the current selection
    func findBestAlignmentTime(preferredAzimuth: Double? = nil) async -> SunAlignmentPoint? {
        guard let location = selectedLocation,
              selectedCelestialObject.type == .sun else { return nil }
        
        return await sunPathService.findBestAlignmentTime(
            poi: location.coordinate,
            date: targetDate,
            preferredAzimuth: preferredAzimuth
        )
    }
    
    /// Get formatted coordinate string for display
    func formattedCoordinates(for coordinate: CLLocationCoordinate2D) -> String {
        let latitude = String(format: "%.6f", coordinate.latitude)
        let longitude = String(format: "%.6f", coordinate.longitude)
        return "\(latitude), \(longitude)"
    }
    
    /// Get distance from user to selected location
    func distanceToSelectedLocation() -> String? {
        guard let selectedLocation = selectedLocation,
              let userLocation = currentUserLocation else { return nil }
        
        let distance = locationService.distance(
            from: userLocation.coordinate,
            to: selectedLocation.coordinate
        )
        
        if distance < 1000 {
            return String(format: "%.0fm", distance)
        } else {
            return String(format: "%.1fkm", distance / 1000)
        }
    }
    
    // MARK: - Private Methods
    
    private func setupLocationObserver() {
        locationService.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                self?.currentUserLocation = location
                
                // Update map region to user location on first update
                if let location = location, self?.mapRegion.center.latitude == 37.7749 {
                    self?.mapRegion = MKCoordinateRegion(
                        center: location.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                }
            }
            .store(in: &cancellables)
        
        locationService.$locationError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                self?.errorMessage = error?.localizedDescription
            }
            .store(in: &cancellables)
    }
    
    private func calculateAlignmentEvents() -> [AlignmentEvent] {
        guard let location = selectedLocation else { return [] }
        var events: [AlignmentEvent] = []
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: targetDate)
        // Calculate positions every hour for 24 hours
        for hour in 0..<24 {
            let eventDate = startDate.addingTimeInterval(TimeInterval(hour * 3600))
                // Generic celestial object support
                let position = AstronomicalCalculations.position(for: selectedCelestialObject, at: eventDate, coordinate: location.coordinate)
                let photographerCoordinate = calculatePhotographerPosition(
                    landmark: location.coordinate,
                    celestialAzimuth: position.azimuth,
                    celestialElevation: position.elevation
                )
                let distance = locationService.distance(
                    from: photographerCoordinate,
                    to: location.coordinate
                )
                let event = AlignmentEvent(
                    timestamp: eventDate,
                    azimuth: position.azimuth,
                    elevation: position.elevation,
                    photographerPosition: photographerCoordinate,
                    alignmentQuality: calculateAlignmentQuality(elevation: position.elevation),
                    distance: distance
                )
                events.append(event)
        }
        return events
    }
    
    private func calculatePhotographerPosition(
        landmark: CLLocationCoordinate2D,
        celestialAzimuth: Double,
        celestialElevation: Double
    ) -> CLLocationCoordinate2D {
        // Simplified calculation - in production would consider terrain, desired framing, etc.
        let distance = 1000.0 // 1km away as default
        let oppositeAzimuth = celestialAzimuth + 180.0
        
        let lat1 = landmark.latitude * .pi / 180
        let lon1 = landmark.longitude * .pi / 180
        let bearing = oppositeAzimuth * .pi / 180
        let angularDistance = distance / 6371000 // Earth radius in meters
        
        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angularDistance) * cos(lat1), cos(angularDistance) - sin(lat1) * sin(lat2))
        
        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }
    
    private func calculateAlignmentQuality(elevation: Double) -> Double {
        // Quality based on elevation - higher is generally better for photography
        if elevation < 0 { return 0.0 } // Below horizon
        if elevation < 5 { return 0.3 } // Very low
        if elevation < 15 { return 0.6 } // Low
        if elevation < 30 { return 0.8 } // Good
        return 1.0 // Excellent
    }
    
    private func calculateProjectionPoints() -> ProjectionPoints {
        guard let location = selectedLocation else {
            // Return default values if no location
            return ProjectionPoints(
                poiProjection: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                celestialProjection: CLLocationCoordinate2D(latitude: 0, longitude: 0)
            )
        }
        
        // Get the projected line from POI to celestial object at 10km distance
        let projectedLine = AstronomicalCalculations.projectedLineToCelestialObject(
            poi: location.coordinate,
            object: selectedCelestialObject,
            date: targetDate,
            distanceKm: 10.0
        )
        
        // The start point is where the POI is (projects straight down)
        let poiProjection = projectedLine.start
        
        // The end point is where the celestial object's line through the POI hits the ground at 10km
        let celestialProjection = projectedLine.end
        
        return ProjectionPoints(
            poiProjection: poiProjection,
            celestialProjection: celestialProjection
        )
    }
}

extension DateFormatter {
    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}

// MARK: - Supporting Data Models

struct AlignmentCalculation: Identifiable {
    let id: UUID
    let name: String
    let landmark: Location
    let celestialObject: CelestialObject
    let calculationDate: Date
    let targetDate: Date
    let alignmentEvents: [AlignmentEvent]
    let projectionPoints: ProjectionPoints // Two ground projection points
}

struct ProjectionPoints {
    let poiProjection: CLLocationCoordinate2D // Where POI projects down to ground
    let celestialProjection: CLLocationCoordinate2D // Where celestial object projects down through POI
}

struct AlignmentEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let azimuth: Double
    let elevation: Double
    let photographerPosition: CLLocationCoordinate2D
    let alignmentQuality: Double
    let distance: Double // Distance from photographer to landmark
}

struct HourlyIntersection: Identifiable {
    let id = UUID()
    let hour: Int
    let time: Date
    let coordinate: CLLocationCoordinate2D
    let sunAzimuth: Double
    let sunElevation: Double
    let distance: Double
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: time)
    }
    
    var hourLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: time)
    }
}