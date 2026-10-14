import SwiftUI
import RuneScaleCore

/// 4x7 inventory from the CONTAINER stream plus worn equipment. Tap a slot = one click on that
/// slot widget in game (eat, drink, wield). The inventory tab must be open in RuneLite.
struct BackpackView: View {
    @Environment(AppModel.self) private var model
    var onClose: () -> Void
    @State private var showEquipment = false

    var body: some View {
        if model.backpackOpen {
            VStack(spacing: 12) {
                HStack {
                    Picker("", selection: $showEquipment) {
                        Text("Backpack").tag(false)
                        Text("Worn").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    Spacer()
                    Button("Close", systemImage: "xmark", action: onClose).labelStyle(.iconOnly)
                }
                if model.lastAck?.result == .widgetHidden {
                    Text("Open the \(showEquipment ? "Worn" : "Backpack") tab from the hand menu first")
                        .font(.caption).foregroundStyle(.yellow)
                }
                if showEquipment {
                    grid(model.equipment, columns: 3, kind: .equipment)
                } else {
                    grid(model.inventory, columns: 4, kind: .inventory)
                }
            }
            .padding(20)
            .frame(width: 420)
            .glassBackgroundEffect()
        }
    }

    private func grid(_ c: RSProtocol.Container, columns: Int, kind: RSProtocol.ContainerKind) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 10), count: columns), spacing: 10) {
            ForEach(c.ids.indices, id: \.self) { i in
                let id = c.ids[i]
                Button { model.clickSlot(kind, slot: i) } label: {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.25))
                        if id >= 0, let img = model.itemIcons[id] {
                            Image(decorative: img, scale: 1).resizable().interpolation(.none)
                                .aspectRatio(contentMode: .fit).padding(10)
                        }
                        if id >= 0, c.quantities[i] > 1 {
                            Text(Self.qty(c.quantities[i])).font(.caption.monospacedDigit()).foregroundStyle(.yellow).padding(6)
                        }
                    }
                    .frame(width: 78, height: 70)
                }
                .buttonStyle(.plain)
                .disabled(id < 0)
                .hoverEffect()
            }
        }
    }

    static func qty(_ q: Int32) -> String {
        q >= 10_000_000 ? "\(q / 1_000_000)M" : q >= 100_000 ? "\(q / 1000)K" : "\(q)"
    }
}
