import AppKit
import SwiftUI

enum GlassRole {
    case regular
    case clear

    var fallbackMaterial: NSVisualEffectView.Material {
        switch self {
        case .regular:
            .sidebar
        case .clear:
            .hudWindow
        }
    }
}

private struct LegacyVisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(
        _ nsView: NSVisualEffectView,
        context: Context
    ) {
        nsView.material = material
    }
}

struct ProgressiveGlassContainer<Content: View>: View {
    let mode: MaterialMode
    let role: GlassRole
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if mode == .compatibility {
            legacyContent
        } else if #available(macOS 26.0, *) {
            liquidGlassContent
        } else {
            legacyContent
        }
    }

    private var legacyContent: some View {
        content()
            .background {
                LegacyVisualEffectView(material: role.fallbackMaterial)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .continuous
                        )
                    )
            }
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(.white.opacity(0.42), lineWidth: 0.75)
            }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private var liquidGlassContent: some View {
        switch role {
        case .regular:
            content()
                .glassEffect(
                    .regular,
                    in: .rect(cornerRadius: cornerRadius)
                )
        case .clear:
            content()
                .glassEffect(
                    .clear,
                    in: .rect(cornerRadius: cornerRadius)
                )
        }
    }
}
