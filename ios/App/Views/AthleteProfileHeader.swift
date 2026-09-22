import SwiftUI

struct AthleteProfileHeader: View {
  var profile: TrainingProfile
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 16) {
        Text(initials).font(.title2.weight(.semibold))
          .foregroundStyle(HybrdStyle.primaryButtonText)
          .frame(width: 64, height: 64).background(HybrdStyle.primaryButton, in: Circle())
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text("ATHLETE PROFILE").font(.caption2.weight(.semibold)).tracking(1)
            .fixedSize(horizontal: false, vertical: true).foregroundStyle(SessionPalette.ink(.violet))
          Text(profile.name.isEmpty ? "Athlete" : profile.name)
            .font(.system(.title, design: .rounded, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
        }
      }
      let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) :
        AnyLayout(HStackLayout(spacing: 8))
      layout {
        stat(profile.athlete?.age().map(String.init) ?? "—", label: "years")
        stat(profile.athlete?.weightKilograms.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—", label: "kg")
        stat(profile.athlete?.heightCentimeters.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—", label: "cm")
      }
      Text("Your starting point. Your next personal best.")
        .font(.subheadline).foregroundStyle(HybrdStyle.muted)
    }
    .padding(22).frame(maxWidth: .infinity, alignment: .leading)
    .background(LinearGradient(colors: [SessionPalette.wash(.violet), SessionPalette.wash(.terra)],
      startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
  }

  private var initials: String {
    let letters = profile.name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
    return letters.isEmpty ? "h" : String(letters).uppercased()
  }
  private func stat(_ value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
      Text(label).font(.caption).foregroundStyle(HybrdStyle.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
  }
}
