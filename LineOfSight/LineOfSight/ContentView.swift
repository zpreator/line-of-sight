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
            projectionPoints: calculation.projectionPoints
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar with save button
            HStack {
                Text("Projection Results")
                    .font(.headline)
                Spacer()
                Button("Save") {
                    saveName = calculation.name
                    showingSaveDialog = true
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.regularMaterial)
            
            // Map with Results
            ResultsMap(
                calculation: calculation,
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

struct ResultsMap: UIViewRepresentable {
    let calculation: AlignmentCalculation
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
        
        // Add projection point annotations
        let poiProjection = ProjectionAnnotation(
            coordinate: calculation.projectionPoints.poiProjection,
            title: "POI Ground Position",
            subtitle: "Mountain top projects here",
            isPOI: true
        )
        mapView.addAnnotation(poiProjection)
        
        let celestialProjection = ProjectionAnnotation(
            coordinate: calculation.projectionPoints.celestialProjection,
            title: "\(calculation.celestialObject.name) Projection",
            subtitle: "\(calculation.celestialObject.name) line at 10km",
            isPOI: false
        )
        mapView.addAnnotation(celestialProjection)
        
        // Draw a line between the two projection points
        let coordinates = [calculation.projectionPoints.poiProjection, calculation.projectionPoints.celestialProjection]
        let polyline = MKPolyline(coordinates: coordinates, count: 2)
        mapView.addOverlay(polyline)
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
            
            if let projectionAnnotation = annotation as? ProjectionAnnotation {
                let identifier = "Projection"
                let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                
                annotationView.annotation = annotation
                annotationView.markerTintColor = projectionAnnotation.isPOI ? .systemBlue : .systemOrange
                annotationView.glyphImage = UIImage(systemName: projectionAnnotation.isPOI ? "mountain.2.fill" : "sun.max.fill")
                annotationView.canShowCallout = true
                
                return annotationView
            }
            
            return nil
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemPurple
                renderer.lineWidth = 3
                renderer.lineDashPattern = [4, 8]
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
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
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    private func colorForCelestialType(_ type: CelestialType) -> Color {
        switch type {
        case .sun: return .yellow
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

class ProjectionAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let isPOI: Bool
    
    init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?, isPOI: Bool) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.isPOI = isPOI
    }
}

#Preview {
    ContentView()
}