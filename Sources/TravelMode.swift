import MapKit

enum TravelMode: String, CaseIterable, Identifiable {
    case pin     = "Pin"
    case driving = "Drive"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pin:     return "mappin.circle.fill"
        case .driving: return "car.fill"
        }
    }

    var baseSpeed: Double {
        switch self {
        case .pin:     return 0
        case .driving: return 11.2  // ~25 mph city
        }
    }

    var transportType: MKDirectionsTransportType {
        return .automobile
    }
}
