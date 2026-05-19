import SwiftUI

/// Four-segment picker for the user to rate the imaging-frame quality of a night,
/// per design §6.2 / Phase 10. Shown in the library's recent-nights row and the
/// document-window inspector.
struct SubQualityPicker: View {
    @Binding var verdict: SubQualityVerdict?
    var label: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(SubQualityVerdict.allCases, id: \.self) { option in
                    let isSelected = verdict == option
                    Button {
                        verdict = isSelected ? nil : option
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: option.symbolName)
                                .font(.caption.weight(.semibold))
                            Text(option.displayName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            isSelected ? option.tint.opacity(0.25) : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(
                                isSelected ? option.tint : .secondary.opacity(0.3),
                                lineWidth: isSelected ? 1 : 0.5
                            )
                        )
                        .foregroundStyle(isSelected ? option.tint : .primary)
                    }
                    .buttonStyle(.plain)
                    .help("Mark this night's imaging frames as \(option.displayName.lowercased())")
                }
            }
        }
    }
}
