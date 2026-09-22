import SwiftUI
import Charts

struct SessionInfographicView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var workout: TrainingWorkout
  @State private var selectedID: String?

  private var breakdown: SessionBreakdown { SessionBreakdown(workout: workout) }
  private var selectedPart: SessionBreakdown.Part? { breakdown.parts.first { $0.id == selectedID } }
  private var displayedAmount: Int { selectedPart?.amount ?? breakdown.total }

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Eyebrow(text: workout.kind == .run ? "Your run, at a glance" : "Your workout, at a glance")
        Spacer(minLength: 8)
        Image(systemName: workout.kind.symbol)
          .foregroundStyle(HybrdStyle.terraText).accessibilityHidden(true)
      }

      if typeSize.isAccessibilitySize {
        VStack(spacing: 22) {
          ring.frame(width: 210, height: 210).frame(maxWidth: .infinity)
          supportingMetrics
        }
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 22) {
            ring.frame(width: 176, height: 176)
            supportingMetrics.fixedSize(horizontal: true, vertical: false)
          }
          .frame(maxWidth: .infinity, alignment: .center)
          VStack(spacing: 20) {
            ring.frame(width: 176, height: 176).frame(maxWidth: .infinity)
            supportingMetrics
          }
        }
      }

      if breakdown.parts.isEmpty {
        Text("A detailed breakdown hasn’t been prescribed for this session.")
          .font(.subheadline).foregroundStyle(HybrdStyle.muted)
      } else {
        Divider().overlay(HybrdStyle.line)
        if !typeSize.isAccessibilitySize {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: workout.kind == .run ? 82 : 120), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(breakdown.parts) { part in phaseButton(part) }
          }
        } else {
          VStack(spacing: 4) {
            ForEach(breakdown.parts) { part in exerciseButton(part) }
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          if let selectedPart {
            Text(selectedPart.title).font(.subheadline.weight(.semibold))
          }
          Text(selectedPart?.detail ?? (workout.kind == .run
            ? "Each arc shows its share of running time. Tap a phase to explore."
            : "Each arc shows its share of working sets. Tap an exercise to explore."))
            .font(.caption).foregroundStyle(HybrdStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
          if workout.kind == .run && breakdown.total != workout.minutes * 60 {
            Text("Session estimate: \(workout.minutes) min. The ring shows timed segments only.")
              .font(.caption).foregroundStyle(HybrdStyle.muted)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
          RoundedRectangle(cornerRadius: 2).fill(HybrdStyle.terra).frame(width: 3)
        }
        .accessibilityElement(children: .combine)
      }
    }
    .padding(20)
    .background {
      RoundedRectangle(cornerRadius: 28)
        .fill(HybrdStyle.surface)
        .overlay(alignment: .top) {
          LinearGradient(colors: [HybrdStyle.terraWash.opacity(0.85), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }
    .overlay(RoundedRectangle(cornerRadius: 28).stroke(HybrdStyle.line.opacity(0.8)))
    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selectedID)
    .sensoryFeedback(.selection, trigger: selectedID)
    .onChange(of: workout.id) { selectedID = nil }
  }

  private var ring: some View {
    ZStack {
      Circle().stroke(HybrdStyle.line.opacity(0.5), lineWidth: 19).padding(12)
      if !breakdown.parts.isEmpty {
        Chart(breakdown.parts) { part in
          SectorMark(angle: .value("Planned amount", part.amount),
            innerRadius: .ratio(0.79), outerRadius: .ratio(0.97),
            angularInset: breakdown.parts.count > 1 ? 3 : 0)
            .cornerRadius(4)
            .foregroundStyle(color(part.tone).opacity(selectedID == nil || selectedID == part.id ? 1 : 0.18))
        }
        .chartLegend(.hidden)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
      }
      VStack(spacing: 4) {
        Text(selectedPart == nil ? "PLANNED" : "SELECTED")
          .font(.system(size: 10, weight: .semibold)).tracking(1.6)
          .foregroundStyle(HybrdStyle.muted)
        Text(breakdown.total == 0 ? "—" : breakdown.value(for: displayedAmount))
          .font(.system(size: typeSize.isAccessibilitySize ? 43 : 38, weight: .semibold, design: .rounded))
          .monospacedDigit().tracking(-1)
        Text(breakdown.unit(for: displayedAmount))
          .font(.system(size: 13, weight: .medium)).foregroundStyle(HybrdStyle.muted)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(selectedPart?.title ?? "Planned session")
      .accessibilityValue(breakdown.total == 0 ? "No breakdown available" : breakdown.spokenValue(for: displayedAmount))
    }
  }

  private var supportingMetrics: some View {
    VStack(alignment: .leading, spacing: 22) {
      metric(value: workout.kind == .run
        ? (Double(workout.distanceMeters) / 1_000).formatted(.number.precision(.fractionLength(0...1)))
        : workout.minutes.formatted(),
        label: workout.kind == .run ? "km planned" : "min planned",
        symbol: workout.kind == .run ? "point.bottomleft.forward.to.point.topright.scurvepath" : "clock")
      metric(value: workout.kind == .run ? effortValue : workout.exercises.count.formatted(),
        label: workout.kind == .run ? effortLabel : "exercises",
        symbol: workout.kind == .run ? "waveform.path" : "dumbbell")
    }
  }

  private var effortValue: String {
    if let range = workout.effort.range(of: "RPE ") { return String(workout.effort[range.upperBound...]) }
    return workout.effort
  }

  private var effortLabel: String { workout.effort.contains("RPE ") ? "target RPE" : "target effort" }

  private func metric(value: String, label: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Image(systemName: symbol).font(.caption).foregroundStyle(HybrdStyle.terraText).accessibilityHidden(true)
      Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
      Text(label).font(.caption).foregroundStyle(HybrdStyle.muted)
    }.accessibilityElement(children: .combine)
  }

  private func phaseButton(_ part: SessionBreakdown.Part) -> some View {
    Button { select(part) } label: {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 5) {
          Text(part.title).font(.caption.weight(.medium)).fixedSize(horizontal: false, vertical: true)
          if selectedID == part.id { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
        }
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(breakdown.value(for: part.amount)).font(.title3.weight(.semibold)).monospacedDigit()
          Text(breakdown.unit(for: part.amount)).font(.caption2).foregroundStyle(HybrdStyle.muted)
        }
        shareBar(part)
        Text(breakdown.share(of: part).formatted(.percent.precision(.fractionLength(0))))
          .font(.caption2).foregroundStyle(HybrdStyle.muted)
      }
      .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
      .padding(8)
      .background(selectedID == part.id ? HybrdStyle.field : .clear, in: RoundedRectangle(cornerRadius: 12))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(part.title)
    .accessibilityValue(accessibleValue(part))
    .accessibilityHint("Shows this breakdown. Select again to show the full session.")
    .accessibilityAddTraits(selectedID == part.id ? .isSelected : [])
  }

  private func exerciseButton(_ part: SessionBreakdown.Part) -> some View {
    Button { select(part) } label: {
      HStack(alignment: .top, spacing: 12) {
        RoundedRectangle(cornerRadius: 3).fill(color(part.tone)).frame(width: 10, height: 10)
          .padding(.top, 5).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 10) {
          Text(part.title).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
          shareBar(part)
          Text("\(breakdown.value(for: part.amount)) \(breakdown.unit(for: part.amount)) · "
            + breakdown.share(of: part).formatted(.percent.precision(.fractionLength(0))))
            .font(.caption).foregroundStyle(HybrdStyle.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if selectedID == part.id {
          Image(systemName: "checkmark").font(.caption.weight(.semibold)).accessibilityHidden(true)
        }
      }
      .padding(10).frame(maxWidth: .infinity, minHeight: 44)
      .background(selectedID == part.id ? HybrdStyle.field : .clear, in: RoundedRectangle(cornerRadius: 12))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(part.title)
    .accessibilityValue(accessibleValue(part))
    .accessibilityHint("Shows this breakdown. Select again to show the full session.")
    .accessibilityAddTraits(selectedID == part.id ? .isSelected : [])
  }

  private func shareBar(_ part: SessionBreakdown.Part) -> some View {
    GeometryReader { geometry in
      Capsule().fill(HybrdStyle.line.opacity(0.65))
        .overlay(alignment: .leading) {
          Capsule().fill(color(part.tone)).frame(width: geometry.size.width * breakdown.share(of: part))
        }
    }.frame(height: 5).accessibilityHidden(true)
  }

  private func select(_ part: SessionBreakdown.Part) {
    selectedID = selectedID == part.id ? nil : part.id
  }

  private func accessibleValue(_ part: SessionBreakdown.Part) -> String {
    breakdown.spokenValue(for: part.amount) + ", "
      + breakdown.share(of: part).formatted(.percent.precision(.fractionLength(0))) + " of the planned session"
  }

  private func color(_ tone: SessionBreakdown.Tone) -> Color {
    switch tone {
    case .terra: HybrdStyle.terra
    case .ink: HybrdStyle.ink
    case .stone: HybrdStyle.chartStone
    case .sand: HybrdStyle.chartSand
    }
  }
}
