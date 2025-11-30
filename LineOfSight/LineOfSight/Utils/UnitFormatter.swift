//
//  UnitFormatter.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/29/25.
//

import Foundation
import SwiftUI

/// Utility for formatting distances and elevations with proper unit conversion
/// All internal calculations use meters, this only affects display
struct UnitFormatter {
    
    // MARK: - Distance Formatting
    
    /// Format distance in meters to user's preferred unit
    /// - Parameters:
    ///   - meters: Distance in meters
    ///   - useMetric: Whether to use metric (km/m) or imperial (mi/ft) units
    /// - Returns: Formatted string with appropriate unit
    static func formatDistance(_ meters: Double, useMetric: Bool = true) -> String {
        if useMetric {
            // Metric: use km for distances >= 1000m, otherwise meters
            if meters >= 1000 {
                return String(format: "%.1fkm", meters / 1000)
            } else {
                return String(format: "%.0fm", meters)
            }
        } else {
            // Imperial: convert to miles or feet
            let feet = meters * 3.28084
            if feet >= 5280 {
                let miles = feet / 5280
                return String(format: "%.1fmi", miles)
            } else {
                return String(format: "%.0fft", feet)
            }
        }
    }
    
    /// Format elevation in meters to user's preferred unit
    /// - Parameters:
    ///   - meters: Elevation in meters
    ///   - useMetric: Whether to use meters or feet
    /// - Returns: Formatted string with appropriate unit
    static func formatElevation(_ meters: Double, useMetric: Bool = true) -> String {
        if useMetric {
            return String(format: "%.0fm", meters)
        } else {
            let feet = meters * 3.28084
            return String(format: "%.0fft", feet)
        }
    }
    
    // MARK: - Unit Settings
    
    /// Check if user prefers metric units
    static func isMetric() -> Bool {
        let units = UserDefaults.standard.string(forKey: "units") ?? "metric"
        return units == "metric"
    }
    
    /// Check if user prefers elevation in meters
    static func useMetersForElevation() -> Bool {
        let units = UserDefaults.standard.string(forKey: "units") ?? "metric"
        return units == "metric"
    }
}

// MARK: - SwiftUI Environment Extension

/// Environment key for accessing unit formatter preferences in SwiftUI views
struct UnitFormatterKey: EnvironmentKey {
    static let defaultValue = UnitFormatterPreferences()
}

extension EnvironmentValues {
    var unitFormatter: UnitFormatterPreferences {
        get { self[UnitFormatterKey.self] }
        set { self[UnitFormatterKey.self] = newValue }
    }
}

/// Preferences for unit formatting that can be passed through environment
struct UnitFormatterPreferences {
    var useMetricDistance: Bool
    var useMetersElevation: Bool
    
    init() {
        self.useMetricDistance = UnitFormatter.isMetric()
        self.useMetersElevation = UnitFormatter.useMetersForElevation()
    }
    
    init(useMetricDistance: Bool, useMetersElevation: Bool) {
        self.useMetricDistance = useMetricDistance
        self.useMetersElevation = useMetersElevation
    }
    
    func formatDistance(_ meters: Double) -> String {
        UnitFormatter.formatDistance(meters, useMetric: useMetricDistance)
    }
    
    func formatElevation(_ meters: Double) -> String {
        UnitFormatter.formatElevation(meters, useMetric: useMetersElevation)
    }
}
