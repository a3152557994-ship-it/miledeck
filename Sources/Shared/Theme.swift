import SwiftUI

enum MileTheme {
    // Distinct industrial highway aesthetic: Asphalt Dark + Highway Emerald + Crisp Road White + Signal Amber
    static let asphalt = Color(red: 0.067, green: 0.094, blue: 0.153)       // #111827
    static let asphaltSurface = Color(red: 0.122, green: 0.161, blue: 0.216) // #1F2937
    static let emerald = Color(red: 0.020, green: 0.588, blue: 0.412)       // #059669
    static let emeraldBright = Color(red: 0.063, green: 0.725, blue: 0.506) // #10B981
    static let emeraldSoft = Color(red: 0.925, green: 0.992, blue: 0.961)   // #ECFDF5
    static let roadWhite = Color(red: 0.957, green: 0.965, blue: 0.973)     // #F4F6F8
    static let card = Color.white
    static let border = Color(red: 0.886, green: 0.910, blue: 0.941)        // #E2E8F0
    static let ink = Color(red: 0.067, green: 0.094, blue: 0.153)           // #111827
    static let muted = Color(red: 0.392, green: 0.455, blue: 0.545)         // #64748B
    static let amber = Color(red: 0.851, green: 0.467, blue: 0.024)         // #D97706
    static let amberSoft = Color(red: 1.000, green: 0.973, blue: 0.922)     // #FFFBEB
    static let personalSlate = Color(red: 0.392, green: 0.455, blue: 0.545) // #64748B
    static let personalSoft = Color(red: 0.945, green: 0.961, blue: 0.976)  // #F1F5F9
    static let medicalBlue = Color(red: 0.145, green: 0.388, blue: 0.922)   // #2563EB
    static let medicalSoft = Color(red: 0.937, green: 0.965, blue: 1.000)
    static let charityPurple = Color(red: 0.486, green: 0.227, blue: 0.929) // #7C3AED
    static let charitySoft = Color(red: 0.961, green: 0.953, blue: 1.000)
    static let dangerRed = Color(red: 0.863, green: 0.149, blue: 0.149)

    static let cornerRadius: CGFloat = 16
}

struct MileCardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(MileTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: MileTheme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MileTheme.cornerRadius, style: .continuous)
                    .stroke(MileTheme.border, lineWidth: 1)
            )
    }
}

extension View {
    func mileCard(padding: CGFloat = 16) -> some View {
        modifier(MileCardModifier(padding: padding))
    }
}
