//
//  LocationService.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import Foundation
import CoreLocation
import Combine

/// Service for managing location-related functionality
@MainActor
class LocationService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isUpdatingLocation = false
    @Published var locationError: LocationError?
    
    // MARK: - Private Properties
    private let locationManager = CLLocationManager()
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: - Public Methods
    
    /// Request location permission from the user
    func requestLocationPermission() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            locationError = .permissionDenied
        default:
            break
        }
    }
    
    /// Start updating location
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestLocationPermission()
            return
        }
        
        isUpdatingLocation = true
        locationError = nil
        locationManager.startUpdatingLocation()
    }
    
    /// Stop updating location
    func stopLocationUpdates() {
        isUpdatingLocation = false
        locationManager.stopUpdatingLocation()
    }
    
    /// Get a single location update
    func getCurrentLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            var hasReturned = false
            
            let timeout = DispatchWorkItem {
                if !hasReturned {
                    hasReturned = true
                    continuation.resume(throwing: LocationError.timeout)
                }
            }
            
            // Set timeout for 10 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
            
            // Subscribe to location updates
            $currentLocation
                .compactMap { $0 }
                .first()
                .sink { location in
                    if !hasReturned {
                        hasReturned = true
                        timeout.cancel()
                        continuation.resume(returning: location)
                    }
                }
                .store(in: &cancellables)
            
            // Start location updates if not already running
            if !isUpdatingLocation {
                startLocationUpdates()
            }
        }
    }
    
    /// Get elevation for a specific coordinate using Open-Elevation API
    func getElevation(for coordinate: CLLocationCoordinate2D) async throws -> Double {
        let urlString = "https://api.open-elevation.com/api/v1/lookup?locations=\(coordinate.latitude),\(coordinate.longitude)"
        
        guard let url = URL(string: urlString) else {
            throw LocationError.elevationServiceUnavailable
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LocationError.elevationServiceUnavailable
        }
        
        let elevationResponse = try JSONDecoder().decode(OpenElevationResponse.self, from: data)
        
        guard let result = elevationResponse.results.first else {
            throw LocationError.elevationServiceUnavailable
        }
        
        return Double(result.elevation)
    }
    
    /// Calculate distance between two coordinates
    func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
    
    /// Calculate bearing from one coordinate to another
    func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        
        let x = sin(deltaLon) * cos(lat2)
        let y = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        
        let bearing = atan2(x, y)
        return fmod(bearing * 180 / .pi + 360, 360)
    }
    
    // MARK: - Private Methods
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
        
        authorizationStatus = locationManager.authorizationStatus
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationService: @preconcurrency CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        locationError = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Handle CLError specifically
        if let clError = error as? CLError {
            switch clError.code {
            case .locationUnknown:
                // This is a transient error - location is temporarily unavailable
                // The location manager will keep trying, so we don't need to report it
                // Don't set locationError or stop updates
                return
            case .denied:
                locationError = .permissionDenied
                isUpdatingLocation = false
                locationManager.stopUpdatingLocation()
            case .network:
                // Network-related error, but location manager will keep trying
                // Only log for debugging, don't show to user
                return
            default:
                // Other errors - report them but don't stop trying
                locationError = LocationError.locationUnavailable(error.localizedDescription)
            }
        } else {
            locationError = LocationError.locationUnavailable(error.localizedDescription)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationError = nil
            if isUpdatingLocation {
                locationManager.startUpdatingLocation()
            }
        case .denied, .restricted:
            // Don't set error here - this gets called during app lifecycle transitions
            // The UI will handle showing appropriate prompts when user tries to use location
            isUpdatingLocation = false
            locationManager.stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - Open-Elevation API Models
struct OpenElevationResponse: Codable {
    let results: [OpenElevationResult]
}

struct OpenElevationResult: Codable {
    let latitude: Double
    let longitude: Double
    let elevation: Int
}

// MARK: - LocationError
enum LocationError: LocalizedError, Equatable {
    case permissionDenied
    case locationUnavailable(String)
    case timeout
    case elevationServiceUnavailable
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location permission denied. Please enable location access in Settings."
        case .locationUnavailable(let message):
            return "Location unavailable: \(message)"
        case .timeout:
            return "Location request timed out. Please try again."
        case .elevationServiceUnavailable:
            return "Elevation data is currently unavailable."
        }
    }
}