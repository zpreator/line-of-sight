//
//  ContentView.swift
//  LineOfSight
//
//  Created by Zachary Preator on 11/18/25.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FindView()
                .tabItem {
                    Image(systemName: "location.magnifyingglass")
                    Text("Find")
                }
                .tag(0)
            
            ResultsView()
                .tabItem {
                    Image(systemName: "map")
                    Text("Results")
                }
                .tag(1)
            
            HistoryView()
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
    var body: some View {
        NavigationView {
            MapSelectionView()
                .navigationTitle("Find Location")
        }
    }
}

struct ResultsView: View {
    var body: some View {
        NavigationView {
            Text("Results View")
                .navigationTitle("Results")
        }
    }
}

struct HistoryView: View {
    var body: some View {
        NavigationView {
            Text("History View")
                .navigationTitle("History")
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

#Preview {
    ContentView()
}