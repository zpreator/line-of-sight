//
//  CalculationProgressSheet.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/28/25.
//

import SwiftUI
import MapKit

/// Bottom sheet showing calculation progress and results
struct CalculationProgressSheet: View {
    let state: CalculationState
    let onDismiss: () -> Void
    let onViewResults: () -> Void
    let onSave: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Only allow dragging down
                            if value.translation.height > 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            // Dismiss if dragged down more than 50 points
                            if value.translation.height > 50 {
                                onDismiss()
                            }
                            dragOffset = 0
                        }
                )
            
            // Content based on state
            switch state {
            case .calculating(let progress):
                CalculatingView(progress: progress)
                
            case .completed(let summary):
                ResultsSummaryView(
                    summary: summary,
                    onViewResults: onViewResults,
                    onSave: onSave,
                    onDismiss: onDismiss
                )
                
            case .error(let message):
                ErrorView(message: message, onDismiss: onDismiss)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 20, y: -5)
        .offset(y: dragOffset)
    }
}

// MARK: - Calculation State

enum CalculationState {
    case calculating(CalculationProgress)
    case completed(CalculationSummary)
    case error(String)
}

struct CalculationProgress {
    let currentStep: CalculationStep
    let sunPositionsCalculated: Int
    let totalSunPositions: Int
    let intersectionsFound: Int
    let totalIntersectionsProcessed: Int
}

enum CalculationStep {
    case preparingSunPositions
    case calculatingIntersections
    case finishing
    
    var description: String {
        switch self {
        case .preparingSunPositions:
            return "Calculating sun positions..."
        case .calculatingIntersections:
            return "Finding positions..."
        case .finishing:
            return "Finalizing results..."
        }
    }
}

struct CalculationSummary {
    let poiName: String
    let date: Date
    let celestialObject: CelestialObject
    let totalIntersections: Int
    let timeRange: ClosedRange<Date>?
    let averageDistance: Double
    let closestDistance: Double
    let farthestDistance: Double
}

// MARK: - Calculating View

struct CalculatingView: View {
    let progress: CalculationProgress
    
    var overallProgress: Double {
        let sunProgress = Double(progress.sunPositionsCalculated) / Double(max(progress.totalSunPositions, 1))
        let intersectionProgress = Double(progress.intersectionsFound) / Double(max(progress.totalIntersectionsProcessed, 1))
        
        switch progress.currentStep {
        case .preparingSunPositions:
            return sunProgress * 0.2
        case .calculatingIntersections:
            return 0.2 + (intersectionProgress * 0.75)
        case .finishing:
            return 0.95
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Progress Icon
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: overallProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut, value: overallProgress)
                
                Image(systemName: "scope")
                    .font(.title2)
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 8) {
                Text(progress.currentStep.description)
                    .font(.headline)
                
                if progress.currentStep == .calculatingIntersections {
                    Text("\(progress.intersectionsFound) positions found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * overallProgress, height: 8)
                            .animation(.easeInOut, value: overallProgress)
                    }
                }
                .frame(height: 8)
                
                Text("\(Int(overallProgress * 100))% complete")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Results Summary View

struct ResultsSummaryView: View {
    let summary: CalculationSummary
    let onViewResults: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Success Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 8) {
                Text("Calculation Complete")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(summary.poiName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Date and Celestial Object
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(formatDate(summary.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: summary.celestialObject.type.icon)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(summary.celestialObject.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
            
            // Stats Grid
            HStack(spacing: 20) {
                StatCard(
                    icon: "mappin.circle.fill",
                    value: "\(summary.totalIntersections)",
                    label: "Positions"
                )
                
                StatCard(
                    icon: "location",
                    value: formatDistance(summary.closestDistance),
                    label: "Closest"
                )
            }
            
            if summary.totalIntersections > 0 {
                // Time Range
                if let timeRange = summary.timeRange {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                        Text(formatTimeRange(timeRange))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Capsule())
                }
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: onViewResults) {
                        HStack {
                            Image(systemName: "map")
                            Text("View on Map")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: onSave) {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Save")
                            }
                            .font(.subheadline)
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Button(action: onDismiss) {
                            HStack {
                                Image(systemName: "xmark")
                                Text("Dismiss")
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            } else {
                // No results found
                VStack(spacing: 12) {
                    Text("No photographer positions found for this date and time.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: onDismiss) {
                        Text("Try Different Settings")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(.vertical, 20)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        return UnitFormatter.formatDistance(meters, useMetric: UnitFormatter.isMetric())
    }
    
    private func formatTimeRange(_ range: ClosedRange<Date>) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: range.lowerBound)) - \(formatter.string(from: range.upperBound))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Error Icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 8) {
                Text("Calculation Failed")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onDismiss) {
                Text("Dismiss")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 20)
    }
}

#Preview("Calculating") {
    CalculationProgressSheet(
        state: .calculating(CalculationProgress(
            currentStep: .calculatingIntersections,
            sunPositionsCalculated: 1440,
            totalSunPositions: 1440,
            intersectionsFound: 234,
            totalIntersectionsProcessed: 450
        )),
        onDismiss: {},
        onViewResults: {},
        onSave: {}
    )
}

#Preview("Completed") {
    CalculationProgressSheet(
        state: .completed(CalculationSummary(
            poiName: "Mt. Hood",
            date: Date(),
            celestialObject: .sun,
            totalIntersections: 234,
            timeRange: Date()...Date().addingTimeInterval(3600 * 8),
            averageDistance: 2500,
            closestDistance: 500,
            farthestDistance: 5000
        )),
        onDismiss: {},
        onViewResults: {},
        onSave: {}
    )
}

#Preview("Error") {
    CalculationProgressSheet(
        state: .error("Unable to download elevation data for this location."),
        onDismiss: {},
        onViewResults: {},
        onSave: {}
    )
}
