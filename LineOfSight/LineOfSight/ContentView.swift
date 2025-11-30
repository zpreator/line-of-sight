//
//  ContentView.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var calculationStore = CalculationStore()
    @AppStorage("accentColor") private var accentColorName: String = "orange"
    
    private var accentColor: Color {
        switch accentColorName {
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "green": return .green
        case "yellow": return .yellow
        case "pink": return .pink
        case "teal": return .teal
        default: return .orange
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FindView(calculationStore: calculationStore, selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "location.magnifyingglass")
                    Text("Find")
                }
                .tag(0)
            
            HistoryView(calculationStore: calculationStore, selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(2)
        }
        .preferredColorScheme(.dark)
        .tint(accentColor)
        .id(accentColorName) // Force re-render when accent color changes
    }
}

// Placeholder views for each tab
struct FindView: View {
    let calculationStore: CalculationStore
    @Binding var selectedTab: Int
    
    var body: some View {
        NavigationView {
            MapSelectionView(calculationStore: calculationStore, selectedTab: $selectedTab)
                .navigationTitle("Find Location")
        }
        .navigationViewStyle(.stack)
    }
}

struct HistoryView: View {
    @ObservedObject var calculationStore: CalculationStore
    @Binding var selectedTab: Int
    
    var body: some View {
        NavigationView {
            HistoryListView(calculationStore: calculationStore, selectedTab: $selectedTab)
                .navigationTitle("History")
        }
        .navigationViewStyle(.stack)
    }
}

struct SettingsView: View {
    @AppStorage("accentColor") private var accentColorName: String = "orange"
    @AppStorage("units") private var units: String = "metric"
    
    private var accentColor: Color {
        switch accentColorName {
        case "blue": return .blue
        case "purple": return .purple
        case "red": return .red
        case "green": return .green
        case "yellow": return .yellow
        case "pink": return .pink
        case "teal": return .teal
        default: return .orange
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Appearance Section
                Section {
                    NavigationLink(destination: AccentColorPickerView(selectedColor: $accentColorName)) {
                        HStack {
                            Text("Accent Color")
                            Spacer()
                            Image(systemName: "circle.fill")
                                .foregroundStyle(accentColor)
                                .font(.caption)
                            Text(accentColorName.capitalized)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Changes the accent color used throughout the app")
                }
                
                // Units Section
                Section {
                    Picker("Units", selection: $units) {
                        Text("Metric (km, m)").tag("metric")
                        Text("Imperial (mi, ft)").tag("imperial")
                    }
                } header: {
                    Text("Units")
                } footer: {
                    Text("Choose your preferred measurement system")
                }
                
                // About Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://github.com/zpreator/line-of-sight")!) {
                        HStack {
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "arrow.up.forward.square")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Calculation Store

// New model for saved calculations with minute intersections
struct SavedCalculation: Identifiable, Codable {
    let id: UUID
    let name: String
    let landmark: Location
    let celestialObject: CelestialObject
    let savedDate: Date
    let targetDate: Date
    let intersections: [SavedIntersection]
    let summary: SavedCalculationSummary
}

struct SavedIntersection: Identifiable, Codable {
    let id: UUID
    let minute: Int
    let time: Date
    let latitude: Double
    let longitude: Double
    let sunAzimuth: Double
    let sunElevation: Double
    let distance: Double
}

struct SavedCalculationSummary: Codable {
    let totalIntersections: Int
    let averageDistance: Double
    let closestDistance: Double
    let farthestDistance: Double
}

class CalculationStore: ObservableObject {
    @Published var currentCalculation: AlignmentCalculation?
    @Published var savedCalculations: [SavedCalculation] = []
    @Published var loadedCalculationId: UUID?
    
    func setCurrentCalculation(_ calculation: AlignmentCalculation) {
        currentCalculation = calculation
    }
    
    func saveCalculation(name: String, landmark: Location, celestialObject: CelestialObject, targetDate: Date, intersections: [MinuteIntersection]) {
        let savedIntersections = intersections.map { intersection in
            SavedIntersection(
                id: intersection.id,
                minute: intersection.minute,
                time: intersection.time,
                latitude: intersection.coordinate.latitude,
                longitude: intersection.coordinate.longitude,
                sunAzimuth: intersection.sunAzimuth,
                sunElevation: intersection.sunElevation,
                distance: intersection.distance
            )
        }
        
        // Calculate summary
        let distances = intersections.map { $0.distance }
        let summary = SavedCalculationSummary(
            totalIntersections: intersections.count,
            averageDistance: distances.isEmpty ? 0 : distances.reduce(0, +) / Double(distances.count),
            closestDistance: distances.min() ?? 0,
            farthestDistance: distances.max() ?? 0
        )
        
        let savedCalculation = SavedCalculation(
            id: UUID(),
            name: name,
            landmark: landmark,
            celestialObject: celestialObject,
            savedDate: Date(),
            targetDate: targetDate,
            intersections: savedIntersections,
            summary: summary
        )
        
        savedCalculations.insert(savedCalculation, at: 0)
        
        // Limit to 50 saved calculations
        if savedCalculations.count > 50 {
            savedCalculations = Array(savedCalculations.prefix(50))
        }
    }
    
    func deleteCalculation(_ calculation: SavedCalculation) {
        savedCalculations.removeAll { $0.id == calculation.id }
    }
    
    func loadCalculation(_ calculation: SavedCalculation) {
        loadedCalculationId = calculation.id
    }
}

struct HistoryListView: View {
    @ObservedObject var calculationStore: CalculationStore
    @Binding var selectedTab: Int
    
    var body: some View {
        Group {
            if calculationStore.savedCalculations.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    
                    Text("No Saved Calculations")
                        .font(.title2)
                        .fontWeight(.medium)
                    
                    Text("Save calculations from the Find tab to access them here.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(calculationStore.savedCalculations) { calculation in
                        HistoryRow(calculation: calculation)
                            .onTapGesture {
                                calculationStore.loadCalculation(calculation)
                                selectedTab = 0 // Switch to Find tab
                            }
                    }
                    .onDelete(perform: deleteCalculations)
                }
            }
        }
    }
    
    private func deleteCalculations(offsets: IndexSet) {
        for index in offsets {
            let calculation = calculationStore.savedCalculations[index]
            calculationStore.deleteCalculation(calculation)
        }
    }
}

// MARK: - Supporting Views

struct HistoryRow: View {
    let calculation: SavedCalculation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(calculation.name)
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: calculation.celestialObject.type.icon)
                            .foregroundColor(colorForCelestialType(calculation.celestialObject.type))
                        Text(calculation.celestialObject.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(calculation.savedDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(calculation.landmark.name ?? "Unknown Location")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Target: \(calculation.targetDate, style: .date)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Summary stats
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle")
                        .font(.caption)
                    Text("\(calculation.summary.totalIntersections) positions")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                if calculation.summary.totalIntersections > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "ruler")
                            .font(.caption)
                        Text(formatDistance(calculation.summary.averageDistance))
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0fm avg", meters)
        } else {
            return String(format: "%.1fkm avg", meters / 1000)
        }
    }
    
    private func colorForCelestialType(_ type: CelestialType) -> Color {
        switch type {
        case .sun: return .yellow
        }
    }
}

struct AccentColorPickerView: View {
    @Binding var selectedColor: String
    @Environment(\.dismiss) private var dismiss
    
    private let colors: [(name: String, color: Color)] = [
        ("orange", .orange),
        ("blue", .blue),
        ("purple", .purple),
        ("red", .red),
        ("green", .green),
        ("yellow", .yellow),
        ("pink", .pink),
        ("teal", .teal)
    ]
    
    var body: some View {
        List {
            ForEach(colors, id: \.name) { colorOption in
                Button(action: {
                    selectedColor = colorOption.name
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(colorOption.color)
                            .font(.title3)
                        
                        Text(colorOption.name.capitalized)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        if selectedColor == colorOption.name {
                            Image(systemName: "checkmark")
                                .foregroundColor(colorOption.color)
                                .font(.body.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Accent Color")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
}