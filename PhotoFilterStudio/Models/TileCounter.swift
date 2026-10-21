//
//  TileCounter.swift
//  PhotoFilterStudio
//
//  Created by the CIS 1951 team on 10/20/26.
//

// @unchecked Sendable turns off Swift's data-race checks here. We fix this in Step 6.
nonisolated final class TileCounter: @unchecked Sendable {
    var count = 0

    func increment() {
        count += 1
    }

    func reset() {
        count = 0
    }
}
