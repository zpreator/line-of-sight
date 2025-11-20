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
    
    // MARK: - Private Properties
    private let locationService: LocationService
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
            do {
                // Get elevation for the coordinate
                let elevation = try await getElevation(for: coordinate)
                
                let location = Location(
                    name: name,
                    coordinate: coordinate,
                    elevation: elevation,
                    source: .map,
                    precision: .approximate
                )
                
                await MainActor.run {
                    self.selectedLocation = location
                    self.isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to get elevation data: \(error.localizedDescription)"
                    self.isLoading = false
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
        
        // Calculate projection points
        let projectionPoints = calculateProjectionPoints()
        
        // Create alignment calculation with current parameters
        let calculation = AlignmentCalculation(
            id: UUID(),
            name: calculationName,
            landmark: location,
            celestialObject: selectedCelestialObject,
            calculationDate: Date(),
            targetDate: targetDate,
            alignmentEvents: calculateAlignmentEvents(),
            projectionPoints: projectionPoints
        )
        
        return calculation
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
    
    private func getElevation(for coordinate: CLLocationCoordinate2D) async throws -> Double {
        // Try to use the location service's Open-Elevation API
        do {
            return try await locationService.getElevation(for: coordinate)
        } catch {
            // If the API fails, use a basic estimation as fallback
            print("Open-Elevation API failed: \(error.localizedDescription). Using estimation.")
            let elevation = estimateElevationFromCoordinate(coordinate)
            return elevation
        }
    }
    
    private func estimateElevationFromCoordinate(_ coordinate: CLLocationCoordinate2D) -> Double {
        // Very basic elevation estimation based on geographic patterns
        // This is just for demo purposes and should be replaced with real data
        
        // Check if we're near known mountain ranges or sea level areas
        let latitude = abs(coordinate.latitude)
        let _ = abs(coordinate.longitude)
        
        // Ocean areas - close to sea level
        if latitude < 10 { return Double.random(in: 0...50) }
        
        // Mountain regions (very rough approximation)
        if latitude > 40 && latitude < 50 {
            // Could be mountainous regions like Alps, Rockies, etc.
            return Double.random(in: 200...2000)
        }
        
        // Default elevation for most populated areas
        return Double.random(in: 50...500)
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