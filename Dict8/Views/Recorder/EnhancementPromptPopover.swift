import SwiftUI

struct PopoverList<Item: Identifiable, Icon: View>: View {
    let title: String
    let items: [Item]
    let selectedId: Item.ID?
    let icon: (Item) -> Icon
    let label: (Item) -> String
    let action: (Item) -> Void
    var toggle: Binding<Bool>? = nil
    var emptyMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let toggle {
                HStack(spacing: 8) {
                    Toggle(title, isOn: toggle).foregroundStyle(.white.opacity(0.9)).font(.headline).lineLimit(1)
                    Spacer()
                }.padding(.horizontal).padding(.top, 8)
            } else {
                Text(title).font(.headline).foregroundStyle(.white.opacity(0.9)).padding(.horizontal).padding(.top, 8)
            }
            Divider().background(Color.white.opacity(0.1))
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if items.isEmpty, let msg = emptyMessage {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.6)).font(.body)
                            Text(msg).foregroundStyle(.white.opacity(0.8)).font(.caption)
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    } else {
                        ForEach(items) { item in
                            let selected = selectedId.map { $0 == item.id } ?? false
                            Button { action(item) } label: {
                                HStack(spacing: 8) {
                                    icon(item)
                                    Text(label(item)).foregroundStyle(.white.opacity(0.9)).font(.caption).lineLimit(1)
                                    if selected { Spacer(); Image(systemName: "checkmark").foregroundColor(.accentColor).font(.caption) }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4).padding(.horizontal, 8).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(selected ? Color.white.opacity(0.1) : .clear).cornerRadius(8)
                        }
                    }
                }.padding(.horizontal)
            }
        }
        .frame(width: 200).frame(maxHeight: 340).padding(.vertical, 8)
        .popoverGlass()
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Popover Glass Modifier

private struct PopoverGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
                .background(Color.black)
        }
    }
}

private extension View {
    func popoverGlass() -> some View {
        modifier(PopoverGlassModifier())
    }
}

struct EnhancementPromptPopover: View {
    @EnvironmentObject var enhancementService: AIEnhancementService

    var body: some View {
        PopoverList(
            title: "AI Enhancement",
            items: enhancementService.allPrompts,
            selectedId: enhancementService.activePrompt?.id,
            icon: { p in Image(systemName: p.icon).font(.caption).foregroundStyle(.white.opacity(0.7)) },
            label: { $0.title },
            action: { p in
                if !enhancementService.isEnhancementEnabled { enhancementService.isEnhancementEnabled = true }
                enhancementService.setActivePrompt(p)
            },
            toggle: $enhancementService.isEnhancementEnabled
        )
    }
}
