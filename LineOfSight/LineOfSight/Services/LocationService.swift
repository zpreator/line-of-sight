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
    
    /// Get elevation for a specific coordinate using external service
    func getElevation(for coordinate: CLLocationCoordinate2D) async throws -> Double {
        // For now, return a default elevation
        // In production, this would call an elevation API service
        return 0.0
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
        locationError = LocationError.locationUnavailable(error.localizedDescription)
        isUpdatingLocation = false
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
            locationError = .permissionDenied
            isUpdatingLocation = false
            locationManager.stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }
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