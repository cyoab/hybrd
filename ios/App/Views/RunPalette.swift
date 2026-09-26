import SwiftUI

/// Run-category colors are independent of the five-zone HR chart palette.
enum RunPalette {
  static func color(_ type: RunWorkoutType) -> Color {
    switch type {
    case .easy: HybrdStyle.adaptive(light: 0x7A9A24, dark: 0xB2D15E)
    case .recovery: SessionPalette.sky
    case .long: SessionPalette.violet
    case .tempo: SessionPalette.gold
    case .intervals, .custom: HybrdStyle.terra
    case .hills: HybrdStyle.adaptive(light: 0x43845A, dark: 0x82C996)
    case .progression: HybrdStyle.adaptive(light: 0x238B87, dark: 0x72D7CF)
    }
  }

  static func ink(_ type: RunWorkoutType) -> Color {
    switch type {
    case .easy: HybrdStyle.adaptive(light: 0x405617, dark: 0xCFEB99)
    case .recovery: SessionPalette.ink(.sky)
    case .long: SessionPalette.ink(.violet)
    case .tempo: SessionPalette.ink(.gold)
    case .intervals, .custom: SessionPalette.ink(.terra)
    case .hills: HybrdStyle.adaptive(light: 0x235635, dark: 0xAFE1B9)
    case .progression: HybrdStyle.adaptive(light: 0x165F5D, dark: 0xA0E8E1)
    }
  }

  static func wash(_ type: RunWorkoutType) -> Color {
    switch type {
    case .easy: HybrdStyle.adaptive(light: 0xF0F6D9, dark: 0x29321E)
    case .recovery: SessionPalette.wash(.sky)
    case .long: SessionPalette.wash(.violet)
    case .tempo: SessionPalette.wash(.gold)
    case .intervals, .custom: SessionPalette.wash(.terra)
    case .hills: HybrdStyle.adaptive(light: 0xE4F0E6, dark: 0x20372A)
    case .progression: HybrdStyle.adaptive(light: 0xE1F5F1, dark: 0x1B3536)
    }
  }

  static func top(_ type: RunWorkoutType) -> Color {
    switch type {
    case .easy: HybrdStyle.adaptive(light: 0xD9EB9C, dark: 0x3C4D22)
    case .recovery: HybrdStyle.adaptive(light: 0xBEDDFA, dark: 0x29425D)
    case .long: HybrdStyle.adaptive(light: 0xD4C3F4, dark: 0x463363)
    case .tempo: HybrdStyle.adaptive(light: 0xFFDE8C, dark: 0x57431B)
    case .intervals, .custom: HybrdStyle.adaptive(light: 0xFFC8AD, dark: 0x653320)
    case .hills: HybrdStyle.adaptive(light: 0xBCDDBF, dark: 0x2B4B36)
    case .progression: HybrdStyle.adaptive(light: 0xAEE5DA, dark: 0x245052)
    }
  }
}
