import SwiftUI

struct HangerIconView: View {
    var size: Double = 24
    var color: Color = .black

    var body: some View {
        HangerIcon()
            .fill(color)
            .frame(width: size, height: size)
    }
}
