//
//  Photo.swift
//  PhotoFilterStudio
//
//  Created by the CIS 1951 team on 10/20/26.
//

import UIKit

/// A campus photo.
struct Photo: Identifiable {
    let id = UUID()

    /// The photo as it appears in the asset catalog.
    let original: UIImage

    /// The filtered version of the photo, if we've made one.
    var filtered: UIImage?
}

extension Photo {
    static let campus = [
        ImageResource.collegeHall,
        .fisherFineArtsLibrary,
        .loveStatue,
        .locustWalk,
        .benFranklinStatue,
        .houstonHall,
        .theQuad,
        .irvineAuditorium,
        .pennMuseum,
        .huntsmanHall,
        .franklinField,
        .vanPeltLibrary,
    ].map { Photo(original: UIImage(resource: $0)) }
}
