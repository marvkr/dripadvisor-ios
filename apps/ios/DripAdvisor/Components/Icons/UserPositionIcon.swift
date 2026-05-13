import SwiftUI

struct UserPositionIcon: View {
    var size: Double = 48
    var color: Color = Color.black.opacity(0.4)
    var lineWidth: Double = 2

    var body: some View {
        Canvas { context, canvasSize in
            let sx = canvasSize.width / 48
            let sy = canvasSize.height / 48

            var base = Path()
            base.move(to: CGPoint(x: 34.5 * sx, y: 32.2484 * sy))
            base.addCurve(to: CGPoint(x: 43 * sx, y: 38.5 * sy), control1: CGPoint(x: 39.6231 * sx, y: 33.5918 * sy), control2: CGPoint(x: 43 * sx, y: 35.8902 * sy))
            base.addCurve(to: CGPoint(x: 24 * sx, y: 46 * sy), control1: CGPoint(x: 43 * sx, y: 42.6422 * sy), control2: CGPoint(x: 34.4934 * sx, y: 46 * sy))
            base.addCurve(to: CGPoint(x: 5 * sx, y: 38.5 * sy), control1: CGPoint(x: 13.5066 * sx, y: 46 * sy), control2: CGPoint(x: 5 * sx, y: 42.6422 * sy))
            base.addCurve(to: CGPoint(x: 13.5 * sx, y: 32.2484 * sy), control1: CGPoint(x: 5 * sx, y: 35.8902 * sy), control2: CGPoint(x: 8.3769 * sx, y: 33.5918 * sy))
            context.stroke(base, with: .color(color), lineWidth: lineWidth)

            var head = Path()
            head.addEllipse(in: CGRect(x: 20 * sx, y: 2 * sy, width: 8 * sx, height: 8 * sy))
            context.stroke(head, with: .color(color), lineWidth: lineWidth)

            var torso = Path()
            torso.move(to: CGPoint(x: 28.1545 * sx, y: 40 * sy))
            torso.addLine(to: CGPoint(x: 19.8465 * sx, y: 40 * sy))
            torso.addLine(to: CGPoint(x: 18.3236 * sx, y: 27 * sy))
            torso.addLine(to: CGPoint(x: 15.0001 * sx, y: 25.375 * sy))
            torso.addLine(to: CGPoint(x: 16.3677 * sx, y: 17.3475 * sy))
            torso.addCurve(to: CGPoint(x: 18.5081 * sx, y: 14.8239 * sy), control1: CGPoint(x: 16.5655 * sx, y: 16.1889 * sy), control2: CGPoint(x: 17.3781 * sx, y: 15.222 * sy))
            torso.addCurve(to: CGPoint(x: 24.0017 * sx, y: 14 * sy), control1: CGPoint(x: 19.7395 * sx, y: 14.39 * sy), control2: CGPoint(x: 22.0658 * sx, y: 14 * sy))
            torso.addCurve(to: CGPoint(x: 29.4339 * sx, y: 14.8027 * sy), control1: CGPoint(x: 24.9656 * sx, y: 14 * sy), control2: CGPoint(x: 27.4065 * sx, y: 14.0975 * sy))
            torso.addCurve(to: CGPoint(x: 31.6324 * sx, y: 17.3475 * sy), control1: CGPoint(x: 30.5822 * sx, y: 15.2025 * sy), control2: CGPoint(x: 31.433 * sx, y: 16.1726 * sy))
            torso.addLine(to: CGPoint(x: 33.0001 * sx, y: 25.375 * sy))
            torso.addLine(to: CGPoint(x: 29.6765 * sx, y: 27 * sy))
            torso.addLine(to: CGPoint(x: 28.1545 * sx, y: 40 * sy))
            torso.closeSubpath()
            context.stroke(torso, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter))
        }
        .frame(width: size, height: size)
    }
}
