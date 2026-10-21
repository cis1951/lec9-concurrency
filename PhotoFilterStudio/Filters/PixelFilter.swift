//
//  PixelFilter.swift
//  PhotoFilterStudio
//
//  Created by the CIS 1951 team on 10/20/26.
//

import UIKit

/// A comic-book filter that runs on the CPU, one small tile of pixels at a time.
nonisolated final class PixelFilter {
    static let tileSize = 6

    let width: Int
    let height: Int

    private let source: UnsafeMutablePointer<UInt8>
    private let output: UnsafeMutablePointer<UInt8>
    private let brightness: UnsafeMutablePointer<UInt8>

    init(_ image: UIImage) {
        let cgImage = image.cgImage!
        width = cgImage.width
        height = cgImage.height

        source = .allocate(capacity: width * height * 4)
        output = .allocate(capacity: width * height * 4)
        brightness = .allocate(capacity: width * height)

        // Decode the image into RGBA bytes.
        let context = CGContext(data: source, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Precompute each pixel's brightness for the edge detection in filterPixel.
        for i in 0..<(width * height) {
            let r = Int(source[i * 4]), g = Int(source[i * 4 + 1]), b = Int(source[i * 4 + 2])
            brightness[i] = UInt8((r * 299 + g * 587 + b * 114) / 1000)
        }
    }

    deinit {
        source.deallocate()
        output.deallocate()
        brightness.deallocate()
    }

    var tileCount: Int {
        (width / Self.tileSize) * (height / Self.tileSize)
    }

    static func tileCount(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return (cgImage.width / tileSize) * (cgImage.height / tileSize)
    }

    /// Filters the tile at `index`. Tiles are numbered row by row, starting at 0.
    func filterTile(_ index: Int) {
        let tilesPerRow = width / Self.tileSize
        let originX = (index % tilesPerRow) * Self.tileSize
        let originY = (index / tilesPerRow) * Self.tileSize
        for y in originY..<(originY + Self.tileSize) {
            for x in originX..<(originX + Self.tileSize) {
                filterPixel(x: x, y: y)
            }
        }
    }

    private func filterPixel(x: Int, y: Int) {
        let levels: Float = 5
        let saturation: Float = 1.3
        let edgeThreshold: Float = 60

        // Edge detection: compare the brightness on either side of the pixel.
        let left = max(x - 1, 0), right = min(x + 1, width - 1)
        let up = max(y - 1, 0), down = min(y + 1, height - 1)
        let dx = Float(brightness[y * width + right]) - Float(brightness[y * width + left])
        let dy = Float(brightness[down * width + x]) - Float(brightness[up * width + x])
        let isEdge = (dx * dx + dy * dy).squareRoot() > edgeThreshold

        // Boost the saturation, posterize each channel, and darken the edges.
        let i = (y * width + x) * 4
        let gray = Float(brightness[y * width + x])
        for channel in 0..<3 {
            var value = gray + (Float(source[i + channel]) - gray) * saturation
            value = min(max(value, 0), 255)
            value = (value / 255 * (levels - 1)).rounded() * (255 / (levels - 1))
            if isEdge {
                value *= 0.15
            }
            output[i + channel] = UInt8(value)
        }
        output[i + 3] = 255
    }

    /// The filtered image.
    var result: UIImage {
        let context = CGContext(data: output, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return UIImage(cgImage: context.makeImage()!)
    }

    /// Filters every tile of `image` and returns the result.
    static func apply(to image: UIImage) -> UIImage {
        let filter = PixelFilter(image)
        for tile in 0..<filter.tileCount {
            filter.filterTile(tile)
        }
        return filter.result
    }
}
