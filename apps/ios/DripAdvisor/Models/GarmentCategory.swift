import SwiftUI

enum GarmentCategory: String, CaseIterable, Identifiable, Codable {
    case top, bottom, dress, shoes, outerwear, accessory

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        case .dress: "Dress"
        case .shoes: "Shoes"
        case .outerwear: "Outerwear"
        case .accessory: "Accessory"
        }
    }

    var systemImage: String {
        switch self {
        case .top: "tshirt.fill"
        case .bottom: "figure.walk"
        case .dress: "figure.dress.line.vertical.figure"
        case .shoes: "shoe.fill"
        case .outerwear: "jacket.fill"
        case .accessory: "handbag.fill"
        }
    }

    var placeholderColor: Color {
        switch self {
        case .top: .pink
        case .bottom: .indigo
        case .dress: .purple
        case .shoes: .orange
        case .outerwear: .teal
        case .accessory: .yellow
        }
    }
}
