import SwiftUI

struct HangerIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 18
        let sy = rect.height / 18
        var p = Path()

        p.move(to: CGPoint(x: 9 * sx, y: 9.792 * sy))
        p.addCurve(to: CGPoint(x: 8.25 * sx, y: 9.042 * sy), control1: CGPoint(x: 8.5859 * sx, y: 9.792 * sy), control2: CGPoint(x: 8.25 * sx, y: 9.4561 * sy))
        p.addLine(to: CGPoint(x: 8.25 * sx, y: 7.25 * sy))
        p.addCurve(to: CGPoint(x: 9 * sx, y: 6.5 * sy), control1: CGPoint(x: 8.25 * sx, y: 6.8359 * sy), control2: CGPoint(x: 8.5859 * sx, y: 6.5 * sy))
        p.addCurve(to: CGPoint(x: 10.1865 * sx, y: 5.918 * sy), control1: CGPoint(x: 9.4668 * sx, y: 6.5 * sy), control2: CGPoint(x: 9.8994 * sx, y: 6.2876 * sy))
        p.addCurve(to: CGPoint(x: 10.4463 * sx, y: 4.588 * sy), control1: CGPoint(x: 10.4785 * sx, y: 5.5415 * sy), control2: CGPoint(x: 10.5703 * sx, y: 5.0694 * sy))
        p.addCurve(to: CGPoint(x: 9.4121 * sx, y: 3.5533 * sy), control1: CGPoint(x: 10.3203 * sx, y: 4.0963 * sy), control2: CGPoint(x: 9.9043 * sx, y: 3.6808 * sy))
        p.addCurve(to: CGPoint(x: 8.082 * sx, y: 3.813 * sy), control1: CGPoint(x: 8.9307 * sx, y: 3.4307 * sy), control2: CGPoint(x: 8.458 * sx, y: 3.5213 * sy))
        p.addCurve(to: CGPoint(x: 7.5 * sx, y: 5 * sy), control1: CGPoint(x: 7.7119 * sx, y: 4.1001 * sy), control2: CGPoint(x: 7.5 * sx, y: 4.5327 * sy))
        p.addCurve(to: CGPoint(x: 6.75 * sx, y: 5.75 * sy), control1: CGPoint(x: 7.5 * sx, y: 5.4141 * sy), control2: CGPoint(x: 7.1641 * sx, y: 5.75 * sy))
        p.addCurve(to: CGPoint(x: 6 * sx, y: 5 * sy), control1: CGPoint(x: 6.3359 * sx, y: 5.75 * sy), control2: CGPoint(x: 6 * sx, y: 5.4141 * sy))
        p.addCurve(to: CGPoint(x: 7.1631 * sx, y: 2.6274 * sy), control1: CGPoint(x: 6 * sx, y: 4.0654 * sy), control2: CGPoint(x: 6.4238 * sx, y: 3.2007 * sy))
        p.addCurve(to: CGPoint(x: 9.7871 * sx, y: 2.101 * sy), control1: CGPoint(x: 7.9033 * sx, y: 2.0542 * sy), control2: CGPoint(x: 8.8565 * sx, y: 1.8608 * sy))
        p.addCurve(to: CGPoint(x: 11.8994 * sx, y: 4.2138 * sy), control1: CGPoint(x: 10.8076 * sx, y: 2.3647 * sy), control2: CGPoint(x: 11.6367 * sx, y: 3.1938 * sy))
        p.addCurve(to: CGPoint(x: 11.3721 * sx, y: 6.8368 * sy), control1: CGPoint(x: 12.1377 * sx, y: 5.1406 * sy), control2: CGPoint(x: 11.9453 * sx, y: 6.0999 * sy))
        p.addCurve(to: CGPoint(x: 9.75 * sx, y: 7.906 * sy), control1: CGPoint(x: 10.9561 * sx, y: 7.3729 * sy), control2: CGPoint(x: 10.3877 * sx, y: 7.7429 * sy))
        p.addLine(to: CGPoint(x: 9.75 * sx, y: 9.042 * sy))
        p.addCurve(to: CGPoint(x: 9 * sx, y: 9.792 * sy), control1: CGPoint(x: 9.75 * sx, y: 9.4561 * sy), control2: CGPoint(x: 9.4141 * sx, y: 9.792 * sy))
        p.closeSubpath()

        p.move(to: CGPoint(x: 14.5 * sx, y: 16 * sy))
        p.addLine(to: CGPoint(x: 3.5 * sx, y: 16 * sy))
        p.addCurve(to: CGPoint(x: 1 * sx, y: 13.5 * sy), control1: CGPoint(x: 2.1211 * sx, y: 16 * sy), control2: CGPoint(x: 1 * sx, y: 14.8784 * sy))
        p.addCurve(to: CGPoint(x: 1.3574 * sx, y: 12.8613 * sy), control1: CGPoint(x: 1 * sx, y: 13.2393 * sy), control2: CGPoint(x: 1.1348 * sx, y: 12.9976 * sy))
        p.addLine(to: CGPoint(x: 8.6074 * sx, y: 8.4033 * sy))
        p.addCurve(to: CGPoint(x: 9.6386 * sx, y: 8.6489 * sy), control1: CGPoint(x: 8.9599 * sx, y: 8.1855 * sy), control2: CGPoint(x: 9.4219 * sx, y: 8.2964 * sy))
        p.addCurve(to: CGPoint(x: 9.3925 * sx, y: 9.6806 * sy), control1: CGPoint(x: 9.8554 * sx, y: 9.0019 * sy), control2: CGPoint(x: 9.746 * sx, y: 9.4638 * sy))
        p.addLine(to: CGPoint(x: 2.5732 * sx, y: 13.8744 * sy))
        p.addCurve(to: CGPoint(x: 3.5 * sx, y: 14.5 * sy), control1: CGPoint(x: 2.7216 * sx, y: 14.2406 * sy), control2: CGPoint(x: 3.081 * sx, y: 14.4999 * sy))
        p.addLine(to: CGPoint(x: 14.5 * sx, y: 14.5 * sy))
        p.addCurve(to: CGPoint(x: 15.4189 * sx, y: 13.8936 * sy), control1: CGPoint(x: 14.9121 * sx, y: 14.5 * sy), control2: CGPoint(x: 15.2666 * sx, y: 14.25 * sy))
        p.addLine(to: CGPoint(x: 11.0068 * sx, y: 11.4146 * sy))
        p.addCurve(to: CGPoint(x: 10.7197 * sx, y: 10.3936 * sy), control1: CGPoint(x: 10.6455 * sx, y: 11.212 * sy), control2: CGPoint(x: 10.5175 * sx, y: 10.7534 * sy))
        p.addCurve(to: CGPoint(x: 11.7412 * sx, y: 10.107 * sy), control1: CGPoint(x: 10.9228 * sx, y: 10.0328 * sy), control2: CGPoint(x: 11.3789 * sx, y: 9.9039 * sy))
        p.addLine(to: CGPoint(x: 16.6172 * sx, y: 12.8463 * sy))
        p.addCurve(to: CGPoint(x: 17 * sx, y: 13.5001 * sy), control1: CGPoint(x: 16.8535 * sx, y: 12.9791 * sy), control2: CGPoint(x: 17 * sx, y: 13.2291 * sy))
        p.addCurve(to: CGPoint(x: 14.5 * sx, y: 16 * sy), control1: CGPoint(x: 17 * sx, y: 14.8785 * sy), control2: CGPoint(x: 15.8789 * sx, y: 16 * sy))
        p.closeSubpath()

        return p
    }
}
