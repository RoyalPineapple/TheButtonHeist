import CoreGraphics

extension CGPath {

    /// Apple "hello" script lettering center-line stroke path.
    /// 48 cubic Bezier curves forming a single continuous pen stroke.
    ///
    /// Normalized to unit width (0...1), aspect ratio (h/w): 0.307
    public static func appleHello() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0.1318, y: 0.1667))
        path.addCurve(to: CGPoint(x: 0.1630, y: 0.0250), control1: CGPoint(x: 0.1422, y: 0.1196), control2: CGPoint(x: 0.1526, y: 0.0722))
        path.addCurve(to: CGPoint(x: 0.1854, y: 0.0000), control1: CGPoint(x: 0.1667, y: 0.0144), control2: CGPoint(x: 0.1742, y: 0.0005))
        path.addCurve(to: CGPoint(x: 0.1931, y: 0.0075), control1: CGPoint(x: 0.1891, y: 0.0000), control2: CGPoint(x: 0.1939, y: 0.0040))
        path.addCurve(to: CGPoint(x: 0.1638, y: 0.1534), control1: CGPoint(x: 0.1840, y: 0.0562), control2: CGPoint(x: 0.1885, y: 0.1105))
        path.addCurve(to: CGPoint(x: 0.1103, y: 0.2221), control1: CGPoint(x: 0.1491, y: 0.1784), control2: CGPoint(x: 0.1324, y: 0.2035))
        path.addCurve(to: CGPoint(x: 0.0056, y: 0.2791), control1: CGPoint(x: 0.0799, y: 0.2477), control2: CGPoint(x: 0.0373, y: 0.2549))
        path.addCurve(to: CGPoint(x: 0.0059, y: 0.2967), control1: CGPoint(x: 0.0011, y: 0.2826), control2: CGPoint(x: 0.0000, y: 0.2967))
        path.addCurve(to: CGPoint(x: 0.1188, y: 0.2317), control1: CGPoint(x: 0.0493, y: 0.2967), control2: CGPoint(x: 0.0860, y: 0.2602))
        path.addCurve(to: CGPoint(x: 0.1664, y: 0.1614), control1: CGPoint(x: 0.1403, y: 0.2130), control2: CGPoint(x: 0.1385, y: 0.1648))
        path.addCurve(to: CGPoint(x: 0.2184, y: 0.1742), control1: CGPoint(x: 0.1843, y: 0.1593), control2: CGPoint(x: 0.2099, y: 0.1585))
        path.addCurve(to: CGPoint(x: 0.2256, y: 0.2820), control1: CGPoint(x: 0.2360, y: 0.2056), control2: CGPoint(x: 0.2202, y: 0.2463))
        path.addCurve(to: CGPoint(x: 0.2368, y: 0.2977), control1: CGPoint(x: 0.2264, y: 0.2884), control2: CGPoint(x: 0.2309, y: 0.2951))
        path.addCurve(to: CGPoint(x: 0.2823, y: 0.2983), control1: CGPoint(x: 0.2503, y: 0.3041), control2: CGPoint(x: 0.2674, y: 0.3015))
        path.addCurve(to: CGPoint(x: 0.3137, y: 0.2810), control1: CGPoint(x: 0.2940, y: 0.2956), control2: CGPoint(x: 0.3049, y: 0.2889))
        path.addCurve(to: CGPoint(x: 0.3449, y: 0.1960), control1: CGPoint(x: 0.3358, y: 0.2605), control2: CGPoint(x: 0.3308, y: 0.2226))
        path.addCurve(to: CGPoint(x: 0.3723, y: 0.1744), control1: CGPoint(x: 0.3502, y: 0.1856), control2: CGPoint(x: 0.3609, y: 0.1750))
        path.addCurve(to: CGPoint(x: 0.3803, y: 0.1862), control1: CGPoint(x: 0.3771, y: 0.1744), control2: CGPoint(x: 0.3803, y: 0.1814))
        path.addCurve(to: CGPoint(x: 0.3662, y: 0.2919), control1: CGPoint(x: 0.3787, y: 0.2216), control2: CGPoint(x: 0.3449, y: 0.2634))
        path.addCurve(to: CGPoint(x: 0.4019, y: 0.2983), control1: CGPoint(x: 0.3734, y: 0.3015), control2: CGPoint(x: 0.3899, y: 0.2993))
        path.addCurve(to: CGPoint(x: 0.4530, y: 0.2847), control1: CGPoint(x: 0.4194, y: 0.2967), control2: CGPoint(x: 0.4375, y: 0.2929))
        path.addCurve(to: CGPoint(x: 0.5004, y: 0.2240), control1: CGPoint(x: 0.4759, y: 0.2730), control2: CGPoint(x: 0.4908, y: 0.2477))
        path.addCurve(to: CGPoint(x: 0.5459, y: 0.0320), control1: CGPoint(x: 0.5252, y: 0.1630), control2: CGPoint(x: 0.5273, y: 0.0951))
        path.addCurve(to: CGPoint(x: 0.5656, y: 0.0061), control1: CGPoint(x: 0.5489, y: 0.0216), control2: CGPoint(x: 0.5550, y: 0.0080))
        path.addCurve(to: CGPoint(x: 0.5768, y: 0.0314), control1: CGPoint(x: 0.5747, y: 0.0048), control2: CGPoint(x: 0.5779, y: 0.0224))
        path.addCurve(to: CGPoint(x: 0.5209, y: 0.2850), control1: CGPoint(x: 0.5675, y: 0.1174), control2: CGPoint(x: 0.5334, y: 0.1995))
        path.addCurve(to: CGPoint(x: 0.5326, y: 0.3023), control1: CGPoint(x: 0.5198, y: 0.2919), control2: CGPoint(x: 0.5260, y: 0.3001))
        path.addCurve(to: CGPoint(x: 0.5883, y: 0.2945), control1: CGPoint(x: 0.5507, y: 0.3073), control2: CGPoint(x: 0.5718, y: 0.3028))
        path.addCurve(to: CGPoint(x: 0.6391, y: 0.2485), control1: CGPoint(x: 0.6088, y: 0.2842), control2: CGPoint(x: 0.6272, y: 0.2679))
        path.addCurve(to: CGPoint(x: 0.7004, y: 0.0317), control1: CGPoint(x: 0.6788, y: 0.1848), control2: CGPoint(x: 0.6770, y: 0.1031))
        path.addCurve(to: CGPoint(x: 0.7185, y: 0.0040), control1: CGPoint(x: 0.7039, y: 0.0213), control2: CGPoint(x: 0.7079, y: 0.0075))
        path.addCurve(to: CGPoint(x: 0.7308, y: 0.0112), control1: CGPoint(x: 0.7230, y: 0.0024), control2: CGPoint(x: 0.7292, y: 0.0067))
        path.addCurve(to: CGPoint(x: 0.7308, y: 0.0365), control1: CGPoint(x: 0.7334, y: 0.0192), control2: CGPoint(x: 0.7316, y: 0.0282))
        path.addCurve(to: CGPoint(x: 0.6796, y: 0.2562), control1: CGPoint(x: 0.7225, y: 0.1113), control2: CGPoint(x: 0.6919, y: 0.1822))
        path.addCurve(to: CGPoint(x: 0.6879, y: 0.2975), control1: CGPoint(x: 0.6775, y: 0.2700), control2: CGPoint(x: 0.6751, y: 0.2916))
        path.addCurve(to: CGPoint(x: 0.7193, y: 0.3015), control1: CGPoint(x: 0.6975, y: 0.3020), control2: CGPoint(x: 0.7089, y: 0.3036))
        path.addCurve(to: CGPoint(x: 0.7632, y: 0.2826), control1: CGPoint(x: 0.7348, y: 0.2980), control2: CGPoint(x: 0.7507, y: 0.2924))
        path.addCurve(to: CGPoint(x: 0.8386, y: 0.1763), control1: CGPoint(x: 0.7976, y: 0.2559), control2: CGPoint(x: 0.8096, y: 0.2085))
        path.addCurve(to: CGPoint(x: 0.8775, y: 0.1529), control1: CGPoint(x: 0.8487, y: 0.1648), control2: CGPoint(x: 0.8623, y: 0.1531))
        path.addCurve(to: CGPoint(x: 0.9076, y: 0.1640), control1: CGPoint(x: 0.8881, y: 0.1526), control2: CGPoint(x: 0.9009, y: 0.1558))
        path.addCurve(to: CGPoint(x: 0.9252, y: 0.2162), control1: CGPoint(x: 0.9188, y: 0.1787), control2: CGPoint(x: 0.9238, y: 0.1979))
        path.addCurve(to: CGPoint(x: 0.9169, y: 0.2615), control1: CGPoint(x: 0.9265, y: 0.2314), control2: CGPoint(x: 0.9233, y: 0.2474))
        path.addCurve(to: CGPoint(x: 0.8895, y: 0.2924), control1: CGPoint(x: 0.9111, y: 0.2738), control2: CGPoint(x: 0.9017, y: 0.2863))
        path.addCurve(to: CGPoint(x: 0.8589, y: 0.2999), control1: CGPoint(x: 0.8802, y: 0.2975), control2: CGPoint(x: 0.8692, y: 0.3017))
        path.addCurve(to: CGPoint(x: 0.8322, y: 0.2818), control1: CGPoint(x: 0.8482, y: 0.2980), control2: CGPoint(x: 0.8362, y: 0.2916))
        path.addCurve(to: CGPoint(x: 0.8272, y: 0.2368), control1: CGPoint(x: 0.8266, y: 0.2676), control2: CGPoint(x: 0.8245, y: 0.2517))
        path.addCurve(to: CGPoint(x: 0.8474, y: 0.1851), control1: CGPoint(x: 0.8304, y: 0.2186), control2: CGPoint(x: 0.8370, y: 0.2003))
        path.addCurve(to: CGPoint(x: 0.8772, y: 0.1638), control1: CGPoint(x: 0.8546, y: 0.1750), control2: CGPoint(x: 0.8658, y: 0.1675))
        path.addCurve(to: CGPoint(x: 1.0000, y: 0.1348), control1: CGPoint(x: 0.9182, y: 0.1539), control2: CGPoint(x: 0.9590, y: 0.1443))
        return path
    }
}

#if canImport(UIKit)
import UIKit

extension UIBezierPath {

    /// Apple "hello" script lettering center-line stroke path.
    /// 48 cubic Bezier curves forming a single continuous pen stroke.
    ///
    /// Normalized to unit width (0...1), aspect ratio (h/w): 0.307
    public static func appleHello() -> UIBezierPath {
        UIBezierPath(cgPath: .appleHello())
    }
}
#endif
