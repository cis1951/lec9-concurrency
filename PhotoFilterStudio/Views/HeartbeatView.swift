//
//  HeartbeatView.swift
//  PhotoFilterStudio
//
//  Created by the CIS 1951 team on 10/20/26.
//

import SwiftUI

struct HeartbeatView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            Image(systemName: "fanblades.fill")
                .rotationEffect(.degrees(seconds.truncatingRemainder(dividingBy: 2) * 180))
        }
    }
}

#Preview {
    HeartbeatView()
}
