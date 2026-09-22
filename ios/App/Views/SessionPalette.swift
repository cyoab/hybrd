import SwiftUI

enum SessionPalette {
  static let sky = HybrdStyle.adaptive(light: 0x438EE4, dark: 0x77B4FF)
  static let mint = HybrdStyle.adaptive(light: 0x29A984, dark: 0x5ED4AE)
  static let gold = HybrdStyle.adaptive(light: 0xD8A624, dark: 0xF1C85B)
  static let violet = HybrdStyle.adaptive(light: 0x8970D8, dark: 0xB8A4F4)
  static let runTop = HybrdStyle.adaptive(light: 0xFFA475, dark: 0x653320)
  static let runGlow = HybrdStyle.adaptive(light: 0xFFE3A0, dark: 0x493723)
  static let liftTop = HybrdStyle.adaptive(light: 0xB9A8F5, dark: 0x3C315E)
  static let liftGlow = HybrdStyle.adaptive(light: 0xD5E6FF, dark: 0x223C51)

  static func color(_ tone: SessionBreakdown.Tone) -> Color {
    switch tone {
    case .sky: sky
    case .mint: mint
    case .gold: gold
    case .terra: HybrdStyle.terra
    case .violet: violet
    case .neutral: HybrdStyle.chartStone
    }
  }

  static func wash(_ tone: SessionBreakdown.Tone) -> Color {
    switch tone {
    case .sky: HybrdStyle.adaptive(light: 0xECF4FF, dark: 0x203147)
    case .mint: HybrdStyle.adaptive(light: 0xE8F7EF, dark: 0x1C3830)
    case .gold: HybrdStyle.adaptive(light: 0xFFF6D9, dark: 0x3F351E)
    case .terra: HybrdStyle.adaptive(light: 0xFFF0E6, dark: 0x412A20)
    case .violet: HybrdStyle.adaptive(light: 0xF1EDFF, dark: 0x312841)
    case .neutral: HybrdStyle.field
    }
  }

  static func ink(_ tone: SessionBreakdown.Tone) -> Color {
    switch tone {
    case .sky: HybrdStyle.adaptive(light: 0x235E9F, dark: 0xAFD4FF)
    case .mint: HybrdStyle.adaptive(light: 0x16654D, dark: 0x8CE4C4)
    case .gold: HybrdStyle.adaptive(light: 0x765A09, dark: 0xF3D985)
    case .terra: HybrdStyle.terraText
    case .violet: HybrdStyle.adaptive(light: 0x6046A1, dark: 0xCCBAFF)
    case .neutral: HybrdStyle.muted
    }
  }

}
