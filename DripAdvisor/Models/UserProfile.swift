import SwiftUI

struct UserProfile: Hashable {
    var displayName: String
    var avatarData: Data?
    var stylePreferences: [String]

    init(
        displayName: String = "You",
        avatarData: Data? = nil,
        stylePreferences: [String] = []
    ) {
        self.displayName = displayName
        self.avatarData = avatarData
        self.stylePreferences = stylePreferences
    }

    var avatarUIImage: UIImage? {
        avatarData.flatMap { UIImage(data: $0) }
    }
}
