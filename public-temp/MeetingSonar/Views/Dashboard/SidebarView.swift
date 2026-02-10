//
//  SidebarView.swift
//  MeetingSonar
//
//  Created by MeetingSonar Team.
//  Copyright © 2024 MeetingSonar. All rights reserved.
//

import SwiftUI

/// Filter options for the sidebar
enum SidebarFilter: String, CaseIterable, Identifiable {
    case all = "All Recordings"
    case smartNotes = "Smart Notes"
    case unprocessed = "Unprocessed"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .all: return "folder"
        case .smartNotes: return "sparkles"
        case .unprocessed: return "mic"
        }
    }
}

/// Sidebar navigation for the dashboard.
/// Implements F-6.1 Sidebar.
struct SidebarView: View {
    
    @Binding var selectedFilter: SidebarFilter
    
    var body: some View {
        List(selection: $selectedFilter) {
            Section(header: Text("Library")) {
                ForEach(SidebarFilter.allCases) { filter in
                    Label(filter.rawValue, systemImage: filter.icon)
                        .tag(filter)
                }
            }
        }
        .listStyle(SidebarListStyle())
        .frame(minWidth: 150)
    }
}
