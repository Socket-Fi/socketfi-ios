import SwiftUI
import UIKit

/// Colors and proportions follow socketfi-app's Signup.tsx access dialog.
enum AccessStyle {
    static let ink = Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255)
    static let text = Color.primary
    static let secondary = Color(uiColor: .secondaryLabel)
    static let surface = Color(uiColor: .systemBackground)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let border = Color(uiColor: .separator).opacity(0.3)
    static let indigo = Color.indigo
    static let violet = Color.purple
    static let security = Color(uiColor: .systemGreen)
    static var headerGradient: LinearGradient {
        LinearGradient(
            colors: [.indigo.opacity(0.085), .cyan.opacity(0.035), surface],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Vector geometry from socketfi-app/public/SOCKETFI.svg.
/// Even-odd fill preserves the two transparent slots in the SocketFi mark.
struct SocketFiBrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let x = rect.midX - side / 2
        let y = rect.midY - side / 2
        var path = Path()
        path.addEllipse(in: CGRect(x: x, y: y, width: side, height: side))
        for offset in [CGFloat(0.3), CGFloat(0.6)] {
            path.addRect(CGRect(x: x + side * offset, y: y + side * 0.4,
                                width: side * 0.1, height: side * 0.2))
        }
        return path
    }
}

struct AccessButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                       value: configuration.isPressed)
    }
}
