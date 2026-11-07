import SwiftUI

/// All · Live · Stills, the filter Explore and the Library share.
enum KindFilter: String, CaseIterable, Identifiable {
    case all = "All", live = "Live", stills = "Stills"

    var id: Self { self }

    func includes(isLive: Bool) -> Bool {
        self == .all || (self == .live) == isLive
    }
}

/// All · Live · Stills styled like the tab bar: one glass capsule, the chosen option in a lighter
/// pill that slides between them, its label in the accent colour.
struct KindFilterPicker: View {
    @Binding var selection: KindFilter
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(KindFilter.allCases) { option in
                let isChosen = selection == option
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { selection = option }
                } label: {
                    Text(option.rawValue)
                        .font(.labelMedium.weight(.semibold))
                        .foregroundStyle(isChosen ? Theme.accent : Theme.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background {
                            if isChosen {
                                Capsule()
                                    .fill(Theme.fill)
                                    .overlay(Capsule().fill(Theme.textPrimary.opacity(0.06)))
                                    .matchedGeometryEffect(id: "chosen", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
        .padding(4)
        .liquidGlass(in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}
