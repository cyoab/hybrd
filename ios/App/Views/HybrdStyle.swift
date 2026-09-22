import SwiftUI

enum HybrdStyle {
  static let terra = Color(hex: 0xFF6B3D)
  static let obsidian = Color(hex: 0x0D0D0E)
  static let sand = Color(hex: 0xF4EDE7)
  static let stone = Color(hex: 0xCBD5E1)
  static let mist = Color(hex: 0xF8FAFC)
  static let background = adaptive(light: 0xF8FAFC, dark: 0x111113)
  static let surface = adaptive(light: 0xFFFFFF, dark: 0x1B1B1E)
  static let ink = adaptive(light: 0x0D0D0E, dark: 0xF8FAFC)
  static let muted = adaptive(light: 0x636B78, dark: 0xA7AFBB)
  static let line = adaptive(light: 0xE1E6ED, dark: 0x37373D)
  static let field = adaptive(light: 0xF0F3F6, dark: 0x29292E)
  static let terraWash = adaptive(light: 0xFFF0E9, dark: 0x35231D)
  static let chartStone = adaptive(light: 0xCBD5E1, dark: 0x718096)
  static let terraText = adaptive(light: 0xBB401B, dark: 0xFF956F)
  static let run = terra
  static let strength = ink
  static let primaryButton = adaptive(light: 0x0D0D0E, dark: 0xF8FAFC)
  static let primaryButtonText = adaptive(light: 0xFFFFFF, dark: 0x0D0D0E)

  static func adaptive(light: UInt32, dark: UInt32) -> Color {
    Color(uiColor: UIColor { traits in
      let value = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(red: CGFloat((value >> 16) & 255) / 255,
        green: CGFloat((value >> 8) & 255) / 255,
        blue: CGFloat(value & 255) / 255, alpha: 1)
    })
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 255) / 255,
      green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
  }
}

struct Eyebrow: View {
  var text: String
  var body: some View {
    Text(text.uppercased())
      .font(.caption.weight(.medium))
      .tracking(1.4)
      .foregroundStyle(HybrdStyle.muted)
  }
}

struct HybrdPrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(HybrdStyle.primaryButtonText)
      .frame(maxWidth: .infinity, minHeight: 50)
      .padding(.horizontal, 16)
      .background(HybrdStyle.primaryButton.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
        in: RoundedRectangle(cornerRadius: 16))
      .contentShape(RoundedRectangle(cornerRadius: 16))
  }
}

struct HybrdSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(HybrdStyle.ink)
      .frame(minHeight: 50)
      .padding(.horizontal, 18)
      .background(configuration.isPressed ? HybrdStyle.field : HybrdStyle.surface,
        in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(HybrdStyle.line, lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: 16))
  }
}

struct DisciplineMark: View {
  var kind: WorkoutKind
  var color: Color? = nil
  var size: CGFloat = 8
  var body: some View {
    RoundedRectangle(cornerRadius: kind == .run ? size / 2 : 2)
      .fill(color ?? (kind == .run ? HybrdStyle.terra : HybrdStyle.ink))
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

struct SessionRow: View {
  @Environment(\.trainingUnits) private var units
  var workout: TrainingWorkout
  var status: String
  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: workout.kind.symbol)
        .font(.title3.weight(.medium))
        .foregroundStyle(workout.kind == .run ? HybrdStyle.terraText : HybrdStyle.ink)
        .frame(width: 44, height: 44)
        .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(workout.title).font(.headline)
        Text(units.summary(workout)).font(.subheadline).foregroundStyle(HybrdStyle.muted)
        Text(status).font(.caption).foregroundStyle(HybrdStyle.muted)
      }
      Spacer(minLength: 0)
      if status == "Completed" {
        Image(systemName: "checkmark").foregroundStyle(HybrdStyle.terraText)
      }
    }
    .padding(.vertical, 5)
    .accessibilityElement(children: .combine)
  }
}

struct MetricTile: View {
  var value: String
  var label: String
  var symbol: String
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Image(systemName: symbol).foregroundStyle(HybrdStyle.terra).accessibilityHidden(true)
      Text(value).font(.title2.weight(.semibold)).monospacedDigit()
      Text(label).font(.caption).foregroundStyle(HybrdStyle.muted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(HybrdStyle.line, lineWidth: 1))
    .accessibilityElement(children: .combine)
  }
}
