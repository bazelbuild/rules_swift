// Copyright 2026 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import MapKit
import SwiftUI

// Exercises the `_MapKit_SwiftUI` cross-import overlay: `Map`, `MapMarker`,
// and the `coordinateRegion:annotationItems:` initializer all live in that
// overlay, not in `MapKit` or `SwiftUI` directly. Under explicit modules the
// overlay must be discovered for these references to resolve.
public struct MapView: View {
    public init() {}

    public var body: some View {
        Map(
            coordinateRegion: .constant(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                latitudinalMeters: 200,
                longitudinalMeters: 200
            )),
            annotationItems: [
                Pin(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)),
            ]
        ) { _ in
            MapMarker(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), tint: .green)
        }
    }
}

public struct Pin: Identifiable {
    public let id = "1"
    public let coordinate: CLLocationCoordinate2D

    public init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
    }
}
