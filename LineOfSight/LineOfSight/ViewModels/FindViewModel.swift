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
                let maxDistance = 50_000.0
                
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
    
}

// Removed unused function calculateAlignment and its dependencies

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