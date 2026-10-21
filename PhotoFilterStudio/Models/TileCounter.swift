//
//  TileCounter.swift
//  PhotoFilterStudio
//
//  Created by the CIS 1951 team on 10/20/26.
//

actor TileCounter {
    var count = 0

    func increment() {
        count += 1
    }

    func reset() {
        count = 0
    }
}
