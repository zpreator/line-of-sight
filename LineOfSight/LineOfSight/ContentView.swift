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
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FindView(calculationStore: calculationStore, selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "location.magnifyingglass")
                    Text("Find")
                }
                .tag(0)
            
            ResultsView(calculationStore: calculationStore)
                .tabItem {
                    Image(systemName: "map")
                    Text("Results")
                }
                .tag(1)
            
            HistoryView(calculationStore: calculationStore, selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .tag(3)
        }
        .preferredColorScheme(.dark)
        .tint(.orange)
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
    }
}

struct ResultsView: View {
    @ObservedObject var calculationStore: CalculationStore
    
    var body: some View {
        NavigationView {
            if let calculation = calculationStore.currentCalculation {
                ResultsMapView(calculation: calculation, calculationStore: calculationStore)
                    .navigationTitle("\(calculation.celestialObject.name) Results")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                ResultsEmptyView()
                    .navigationTitle("Results")
            }
        }
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
    }
    
    private func deleteCalculations(offsets: IndexSet) {
        for index in offsets {
            let calculation = calculationStore.savedCalculations[index]
            calculationStore.deleteCalculation(calculation)
        }
    }
}

struct SettingsView: View {
    var body: some View {
        NavigationView {
            Text("Settings View")
                .navigationTitle("Settings")
        }
    }
}

// MARK: - Calculation Store

class CalculationStore: ObservableObject {
    @Published var currentCalculation: AlignmentCalculation?
    @Published var savedCalculations: [AlignmentCalculation] = []
    
    func setCurrentCalculation(_ calculation: AlignmentCalculation) {
        currentCalculation = calculation
    }
    
    func saveCurrentCalculation(name: String = "") {
        guard let calculation = currentCalculation else { return }
        
        // Create a copy with the provided name or use existing name
        let finalName = name.isEmpty ? calculation.name : name
        let savedCalculation = AlignmentCalculation(
            id: UUID(),
            name: finalName,
            landmark: calculation.landmark,
            celestialObject: calculation.celestialObject,
            calculationDate: Date(), // Save current date as when it was saved
            targetDate: calculation.targetDate,
            alignmentEvents: calculation.alignmentEvents,
            optimalPositions: calculation.optimalPositions
        )
        
        savedCalculations.insert(savedCalculation, at: 0) // Add to beginning
        
        // Limit to 50 saved calculations
        if savedCalculations.count > 50 {
            savedCalculations = Array(savedCalculations.prefix(50))
        }
    }
    
    func deleteCalculation(_ calculation: AlignmentCalculation) {
        savedCalculations.removeAll { $0.id == calculation.id }
    }
    
    func loadCalculation(_ calculation: AlignmentCalculation) {
        currentCalculation = calculation
    }
}

// MARK: - Results Views

struct ResultsMapView: View {
    let calculation: AlignmentCalculation
    @ObservedObject var calculationStore: CalculationStore
    @State private var selectedFilter: ResultsFilter = .all
    @State private var showingSaveAlert = false
    @State private var showingSaveDialog = false
    @State private var saveName = ""
    @State private var mapRegion: MKCoordinateRegion
    
    init(calculation: AlignmentCalculation, calculationStore: CalculationStore) {
        self.calculation = calculation
        self.calculationStore = calculationStore
        
        // Initialize map region centered on the landmark
        self._mapRegion = State(initialValue: MKCoordinateRegion(
            center: calculation.landmark.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))
    }
    
    var filteredPositions: [OptimalPosition] {
        switch selectedFilter {
        case .all:
            return calculation.optimalPositions
        case .excellent:
            return calculation.optimalPositions.filter { $0.quality > 0.8 }
        case .good:
            return calculation.optimalPositions.filter { $0.quality > 0.6 }
        case .nearby:
            return calculation.optimalPositions.filter { $0.distance < 5000 } // Within 5km
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Controls
            VStack(spacing: 12) {
                HStack {
                    Text("Filter Results")
                        .font(.headline)
                    Spacer()
                    Button("Save") {
                        saveName = calculation.name
                        showingSaveDialog = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(ResultsFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                title: filter.displayName,
                                count: countForFilter(filter),
                                isSelected: selectedFilter == filter
                            ) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding()
            .background(.regularMaterial)
            
            // Map with Results
            ResultsMap(
                calculation: calculation,
                positions: filteredPositions,
                region: $mapRegion
            )
        }
        .sheet(isPresented: $showingSaveDialog) {
            NavigationView {
                VStack(spacing: 20) {
                    Text("Save Find")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    TextField("Find name", text: $saveName)
                        .textFieldStyle(.roundedBorder)
                    
                    Spacer()
                }
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingSaveDialog = false
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            calculationStore.saveCurrentCalculation(name: saveName)
                            showingSaveDialog = false
                        }
                        .disabled(saveName.isEmpty)
                    }
                }
            }
        }
    }
    
    private func countForFilter(_ filter: ResultsFilter) -> Int {
        switch filter {
        case .all:
            return calculation.optimalPositions.count
        case .excellent:
            return calculation.optimalPositions.filter { $0.quality > 0.8 }.count
        case .good:
            return calculation.optimalPositions.filter { $0.quality > 0.6 }.count
        case .nearby:
            return calculation.optimalPositions.filter { $0.distance < 5000 }.count
        }
    }
}

struct ResultsEmptyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Results Yet")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Calculate an alignment from the Find tab to see results here.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    
                    Text("Save calculations from the Results tab to access them here.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(calculationStore.savedCalculations) { calculation in
                        HistoryRow(calculation: calculation) {
                            calculationStore.loadCalculation(calculation)
                            selectedTab = 1 // Switch to Results tab
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

enum ResultsFilter: CaseIterable {
    case all, excellent, good, nearby
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .excellent: return "Excellent"
        case .good: return "Good+"
        case .nearby: return "Nearby"
        }
    }
}

struct FilterChip: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Text("(\(count))")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                                            .fill(isSelected ? .orange : .gray.opacity(0.3))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
    }
}

struct ResultsMap: UIViewRepresentable {
    let calculation: AlignmentCalculation
    let positions: [OptimalPosition]
    @Binding var region: MKCoordinateRegion
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update region if needed
        if !mapView.region.isEqual(to: region, tolerance: 0.001) {
            mapView.setRegion(region, animated: true)
        }
        
        // Remove existing annotations
        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        
        // Add landmark annotation
        let landmarkAnnotation = LandmarkAnnotation(location: calculation.landmark)
        mapView.addAnnotation(landmarkAnnotation)
        
        // Add position annotations
        for (index, position) in positions.enumerated() {
            let annotation = PositionAnnotation(position: position, rank: index + 1)
            mapView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: ResultsMap
        
        init(_ parent: ResultsMap) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.region = mapView.region
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
                            if annotation is LandmarkAnnotation {
                let identifier = "Landmark"
                let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                
                annotationView.annotation = annotation
                annotationView.markerTintColor = .red
                annotationView.glyphImage = UIImage(systemName: "target")
                annotationView.canShowCallout = true
                
                return annotationView
            }
            
            if let positionAnnotation = annotation as? PositionAnnotation {
                let identifier = "Position"
                let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                
                annotationView.annotation = annotation
                annotationView.markerTintColor = colorForQuality(positionAnnotation.position.quality)
                annotationView.glyphText = "\(positionAnnotation.rank)"
                annotationView.canShowCallout = true
                
                return annotationView
            }
            
            return nil
        }
        
        private func colorForQuality(_ quality: Double) -> UIColor {
            if quality > 0.8 { return .systemGreen }
            if quality > 0.6 { return .systemOrange }
            if quality > 0.3 { return .systemYellow }
            return .systemRed
        }
    }
}

struct HistoryRow: View {
    let calculation: AlignmentCalculation
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
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
                    
                    Text(calculation.landmark.name ?? "Unknown Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Target: \(calculation.targetDate, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(calculation.calculationDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(calculation.optimalPositions.count) positions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func colorForCelestialType(_ type: CelestialType) -> Color {
        switch type {
        case .sun: return .yellow
        case .moon: return .gray
        case .planet: return .blue
        case .star: return .white
        }
    }
}

// MARK: - Map Annotations

class LandmarkAnnotation: NSObject, MKAnnotation {
    let location: Location
    
    var coordinate: CLLocationCoordinate2D {
        return location.coordinate
    }
    
    var title: String? {
        return location.name ?? "Target Location"
    }
    
    var subtitle: String? {
        return "Landmark"
    }
    
    init(location: Location) {
        self.location = location
    }
}

class PositionAnnotation: NSObject, MKAnnotation {
    let position: OptimalPosition
    let rank: Int
    
    var coordinate: CLLocationCoordinate2D {
        return position.coordinate
    }
    
    var title: String? {
        return "Position #\(rank)"
    }
    
    var subtitle: String? {
        return String(format: "Quality: %.0f%% • %.1fkm away", position.quality * 100, position.distance / 1000)
    }
    
    init(position: OptimalPosition, rank: Int) {
        self.position = position
        self.rank = rank
    }
}

#Preview {
    ContentView()
}