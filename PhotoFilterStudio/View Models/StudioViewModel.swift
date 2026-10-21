//
//  StudioViewModel.swift
//  PhotoFilterStudio
//
//  Created by the CIS 1951 team on 10/20/26.
//

import SwiftUI

@Observable class StudioViewModel {
    var photos = Photo.campus
    var elapsed: Duration?
    var tilesProcessed = 0

    let expectedTiles = Photo.campus.map { PixelFilter.tileCount(of: $0.original) }.reduce(0, +)
    let counter = TileCounter()

    func reset() {
        for i in photos.indices {
            photos[i].filtered = nil
        }
        elapsed = nil
        tilesProcessed = 0
    }

    func filterOnMainActor() {
        // TODO: Step 1
    }

    func filterInBackground() {
        // TODO: Step 2
    }

    func filterInParallel() {
        // TODO: Step 4
    }
}
