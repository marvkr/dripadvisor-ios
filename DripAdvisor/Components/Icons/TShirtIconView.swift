import SwiftUI

struct TShirtIconView: View {
    var size: Double = 24
    var color: Color = .black
    var lineWidth: Double = 1.5

    var body: some View {
        Canvas { context, canvasSize in
            let sx = canvasSize.width / 18
            let sy = canvasSize.height / 18
            let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

            var torso = Path()
            torso.move(to: CGPoint(x: 13.151 * sx, y: 7 * sy))
            torso.addCurve(to: CGPoint(x: 12.969 * sx, y: 11 * sy), control1: CGPoint(x: 13.042 * sx, y: 8.236 * sy), control2: CGPoint(x: 12.973 * sx, y: 9.574 * sy))
            torso.addCurve(to: CGPoint(x: 13.25 * sx, y: 16.25 * sy), control1: CGPoint(x: 12.964 * sx, y: 12.918 * sy), control2: CGPoint(x: 13.077 * sx, y: 14.678 * sy))
            torso.addLine(to: CGPoint(x: 9 * sx, y: 16.25 * sy))
            torso.addLine(to: CGPoint(x: 4.75 * sx, y: 16.25 * sy))
            torso.addCurve(to: CGPoint(x: 5.031 * sx, y: 11 * sy), control1: CGPoint(x: 4.923 * sx, y: 14.678 * sy), control2: CGPoint(x: 5.036 * sx, y: 12.918 * sy))
            torso.addCurve(to: CGPoint(x: 4.849 * sx, y: 7 * sy), control1: CGPoint(x: 5.027 * sx, y: 9.574 * sy), control2: CGPoint(x: 4.958 * sx, y: 8.236 * sy))
            context.stroke(torso, with: .color(color), style: style)

            var sleeves = Path()
            sleeves.move(to: CGPoint(x: 15.25 * sx, y: 8.75 * sy))
            sleeves.addLine(to: CGPoint(x: 17 * sx, y: 8 * sy))
            sleeves.addLine(to: CGPoint(x: 15.395 * sx, y: 4.187 * sy))
            sleeves.addCurve(to: CGPoint(x: 14.011 * sx, y: 3.016 * sy), control1: CGPoint(x: 15.147 * sx, y: 3.598 * sy), control2: CGPoint(x: 14.633 * sx, y: 3.163 * sy))
            sleeves.addLine(to: CGPoint(x: 11.748 * sx, y: 2.483 * sy))
            sleeves.addCurve(to: CGPoint(x: 9 * sx, y: 5.261 * sy), control1: CGPoint(x: 11.751 * sx, y: 2.493 * sy), control2: CGPoint(x: 11.751 * sx, y: 5.261 * sy))
            sleeves.addCurve(to: CGPoint(x: 6.252 * sx, y: 2.483 * sy), control1: CGPoint(x: 6.249 * sx, y: 5.261 * sy), control2: CGPoint(x: 6.249 * sx, y: 2.493 * sy))
            sleeves.addLine(to: CGPoint(x: 3.989 * sx, y: 3.016 * sy))
            sleeves.addCurve(to: CGPoint(x: 2.605 * sx, y: 4.187 * sy), control1: CGPoint(x: 3.367 * sx, y: 3.163 * sy), control2: CGPoint(x: 2.853 * sx, y: 3.598 * sy))
            sleeves.addLine(to: CGPoint(x: 1 * sx, y: 8 * sy))
            sleeves.addLine(to: CGPoint(x: 2.75 * sx, y: 8.75 * sy))
            context.stroke(sleeves, with: .color(color), style: style)
        }
        .frame(width: size, height: size)
    }
}
