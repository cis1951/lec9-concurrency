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
        let start = ContinuousClock.now
        for i in photos.indices {
            photos[i].filtered = PixelFilter.apply(to: photos[i].original)
        }
        elapsed = start.duration(to: .now)
    }

    func filterInBackground() {
        Task {
            let start = ContinuousClock.now
            await counter.reset()
            for i in photos.indices {
                photos[i].filtered = await render(photos[i].original)
            }
            tilesProcessed = await counter.count
            elapsed = start.duration(to: .now)
        }
    }

    @concurrent
    func render(_ image: UIImage) async -> UIImage {
        let filter = PixelFilter(image)
        for tile in 0..<filter.tileCount {
            filter.filterTile(tile)
            await counter.increment()
        }
        return filter.result
    }

    func filterInParallel() {
        Task {
            let start = ContinuousClock.now
            await counter.reset()
            await withTaskGroup { group in
                for (index, photo) in photos.enumerated() {
                    group.addTask {
                        (index, await self.render(photo.original))
                    }
                }
                for await (index, image) in group {
                    photos[index].filtered = image
                }
            }
            tilesProcessed = await counter.count
            elapsed = start.duration(to: .now)
        }
    }
}
