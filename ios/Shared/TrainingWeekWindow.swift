import Foundation

/// A date-based paging window. Calendar arithmetic preserves local days across DST.
struct TrainingWeekWindow {
  private(set) var weeks: [Date] = []
  private var calendar: Calendar
  private let buffer = 8

  init(containing date: Date, calendar: Calendar = .current) {
    self.calendar = calendar
    self.calendar.firstWeekday = 2
    let week = startOfWeek(containing: date)
    weeks = (-buffer...buffer).map { addingDays($0 * 7, to: week) }
  }

  func startOfWeek(containing date: Date) -> Date {
    calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
  }

  func addingDays(_ days: Int, to date: Date) -> Date {
    calendar.date(byAdding: .day, value: days, to: date) ?? date
  }

  /// A swipe preserves the selected weekday, including across month and year boundaries.
  func selection(in week: Date, matching selectedDate: Date) -> Date {
    let offset = calendar.dateComponents([.day], from: startOfWeek(containing: selectedDate),
      to: calendar.startOfDay(for: selectedDate)).day ?? 0
    return addingDays(offset, to: startOfWeek(containing: week))
  }

  mutating func reveal(_ date: Date) {
    let week = startOfWeek(containing: date)
    guard let index = weeks.firstIndex(of: week) else {
      // A distant date-picker jump doesn't allocate all intervening weeks.
      weeks = (-buffer...buffer).map { addingDays($0 * 7, to: week) }
      return
    }
    if index < 3, let first = weeks.first {
      weeks.insert(contentsOf: (-buffer..<0).map { addingDays($0 * 7, to: first) }, at: 0)
    } else if index >= weeks.count - 3, let last = weeks.last {
      weeks.append(contentsOf: (1...buffer).map { addingDays($0 * 7, to: last) })
    }
  }
}
