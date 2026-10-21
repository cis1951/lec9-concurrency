//
//  RootView.swift
//  PhotoFilterStudio
//
//  Created by the CIS 1951 team on 10/20/26.
//

import SwiftUI

struct RootView: View {
    @State var viewModel = StudioViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack {
                    LabeledContent("Last run", value: lastRun)
                    LabeledContent("Tiles processed", value: tilesProcessed)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(viewModel.photos) { photo in
                            Image(uiImage: photo.filtered ?? photo.original)
                                .resizable()
                                .scaledToFit()
                                .clipShape(.rect(cornerRadius: 8))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Photo Filter Studio")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HeartbeatView()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset", systemImage: "arrow.counterclockwise") {
                        viewModel.reset()
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Main Actor") {
                        viewModel.filterOnMainActor()
                    }
                    Button("Background") {
                        viewModel.filterInBackground()
                    }
                    Button("Parallel") {
                        viewModel.filterInParallel()
                    }
                }
            }
        }
    }

    var lastRun: String {
        guard let elapsed = viewModel.elapsed else { return "—" }
        return elapsed.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 2)))
    }

    var tilesProcessed: String {
        "\(viewModel.tilesProcessed.formatted()) / \(viewModel.expectedTiles.formatted())"
    }
}

#Preview {
    RootView()
}
