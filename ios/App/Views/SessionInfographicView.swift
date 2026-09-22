import SwiftUI
import Charts

struct SessionInfographicView: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var workout: TrainingWorkout
  @State private var selectedID: String?
  @State private var showingZones = false

  private var breakdown: SessionBreakdown { SessionBreakdown(workout: workout) }
  private var selectedPart: SessionBreakdown.Part? { breakdown.parts.first { $0.id == selectedID } }
  private var displayedAmount: Int { selectedPart?.amount ?? breakdown.total }

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      if typeSize.isAccessibilitySize {
        VStack(spacing: 20) {
          ring.frame(width: 210, height: 210).frame(maxWidth: .infinity)
          firstMetric
          secondMetric
        }.frame(maxWidth: .infinity)
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 8) {
            firstMetric.frame(width: 62)
            ring.frame(width: 164, height: 164)
            secondMetric.frame(width: 62)
          }.frame(maxWidth: .infinity)
          VStack(spacing: 18) {
            ring.frame(width: 180, height: 180).frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 30) { firstMetric; secondMetric }.frame(maxWidth: .infinity)
          }
        }
      }

      HStack(alignment: .center) {
        Text(workout.kind == .run ? "Planned time by HR zone" : "Your working sets")
          .font(.subheadline.weight(.semibold))
        Spacer(minLength: 4)
        if workout.kind == .run {
          Button("About heart-rate zones", systemImage: "info.circle") { showingZones = true }
            .labelStyle(.iconOnly).font(.body)
            .foregroundStyle(HybrdStyle.ink)
            .frame(width: 44, height: 44)
        }
      }

      if breakdown.parts.isEmpty {
        Text("A detailed breakdown hasn’t been prescribed for this session.")
          .font(.subheadline).foregroundStyle(HybrdStyle.muted)
      } else {
        if !typeSize.isAccessibilitySize {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: workout.kind == .run ? 86 : 125), spacing: 10)],
            alignment: .leading, spacing: 10) {
            ForEach(breakdown.parts) { part in partButton(part) }
          }
        } else {
          VStack(spacing: 10) {
            ForEach(breakdown.parts) { part in accessiblePartButton(part) }
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          if let selectedPart {
            Text(selectedPart.title).font(.subheadline.weight(.semibold))
            Text(selectedPart.detail).font(.subheadline).foregroundStyle(HybrdStyle.muted)
          } else {
            Text(workout.kind == .run
              ? "Tap a zone to explore its intervals."
              : "Tap an exercise to explore its sets.")
              .font(.caption).foregroundStyle(HybrdStyle.muted)
          }
          if workout.kind == .run {
            Text("Zone targets only · personal BPM ranges aren’t connected.")
              .font(.caption).foregroundStyle(HybrdStyle.muted)
            if breakdown.total != workout.minutes * 60 {
              Text("Session estimate: \(workout.minutes) min. The ring shows timed segments only.")
                .font(.caption).foregroundStyle(HybrdStyle.muted)
            }
          }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
      }
    }
    .padding(.horizontal, 20).padding(.vertical, 16)
    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selectedID)
    .sensoryFeedback(.selection, trigger: selectedID)
    .onChange(of: workout.id) { selectedID = nil }
    .sheet(isPresented: $showingZones) { HeartRateZoneGuideView() }
  }

  private var ring: some View {
    ZStack {
      Circle().fill(HybrdStyle.surface.opacity(0.62)).padding(15)
      Circle().stroke(HybrdStyle.ink.opacity(0.07), lineWidth: 17).padding(11)
      if !breakdown.parts.isEmpty {
        Chart(breakdown.parts) { part in
          SectorMark(angle: .value("Planned amount", part.amount),
            innerRadius: .ratio(0.81), outerRadius: .ratio(0.98),
            angularInset: breakdown.parts.count > 1 ? 2.5 : 0)
            .cornerRadius(4)
            .foregroundStyle(SessionPalette.color(part.tone)
              .opacity(selectedID == nil || selectedID == part.id ? 1 : 0.2))
        }
        .chartLegend(.hidden).allowsHitTesting(false).accessibilityHidden(true)
      }
      VStack(spacing: 4) {
        Text(selectedPart == nil ? "PLANNED" : "SELECTED")
          .font(.system(size: 10, weight: .semibold)).tracking(1.5)
          .foregroundStyle(HybrdStyle.ink.opacity(0.75))
        Text(breakdown.total == 0 ? "—" : breakdown.value(for: displayedAmount))
          .font(.system(size: typeSize.isAccessibilitySize ? 43 : 38, weight: .semibold, design: .rounded))
          .monospacedDigit().tracking(-1)
        Text(breakdown.unit(for: displayedAmount))
          .font(.system(size: 13, weight: .medium)).foregroundStyle(HybrdStyle.ink.opacity(0.75))
      }
      .foregroundStyle(HybrdStyle.ink)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(selectedPart?.title ?? "Planned session")
      .accessibilityValue(breakdown.total == 0 ? "No breakdown available" : breakdown.spokenValue(for: displayedAmount))
    }
  }

  private var firstMetric: some View {
    metric(value: workout.kind == .run
      ? (Double(workout.distanceMeters) / 1_000).formatted(.number.precision(.fractionLength(0...1)))
      : workout.minutes.formatted(),
      label: workout.kind == .run ? "km planned" : "min planned",
      symbol: workout.kind == .run ? "point.bottomleft.forward.to.point.topright.scurvepath" : "clock")
  }

  private var secondMetric: some View {
    metric(value: workout.kind == .run ? workout.primaryHeartRateZone?.shortTitle ?? "—" : workout.exercises.count.formatted(),
      label: workout.kind == .run ? (workout.primaryHeartRateZone == nil ? "HR not set" : workout.heartRateTargetCaption) : "exercises",
      symbol: workout.kind == .run ? "heart.fill" : "dumbbell")
  }

  private func metric(value: String, label: String, symbol: String) -> some View {
    VStack(spacing: 6) {
      Image(systemName: symbol).font(.subheadline).accessibilityHidden(true)
      Text(value).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
      Text(label).font(.caption).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(HybrdStyle.ink)
    .accessibilityElement(children: .combine)
  }

  private func partButton(_ part: SessionBreakdown.Part) -> some View {
    Button { select(part) } label: {
      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .top, spacing: 3) {
          Text(part.title).font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          if selectedID == part.id { Image(systemName: "checkmark").font(.caption2.weight(.bold)) }
        }
        if let subtitle = part.subtitle {
          Text(subtitle).font(.caption2).foregroundStyle(SessionPalette.ink(part.tone))
        }
        HStack(alignment: .firstTextBaseline, spacing: 3) {
          Text(breakdown.value(for: part.amount)).font(.title3.weight(.semibold)).monospacedDigit()
          Text(breakdown.unit(for: part.amount)).font(.caption2)
        }
        shareBar(part)
        Text(breakdown.share(of: part).formatted(.percent.precision(.fractionLength(0))))
          .font(.caption2)
      }
      .foregroundStyle(SessionPalette.ink(part.tone))
      .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
      .padding(12)
      .background(SessionPalette.wash(part.tone), in: RoundedRectangle(cornerRadius: 18))
      .overlay(RoundedRectangle(cornerRadius: 18)
        .stroke(selectedID == part.id ? SessionPalette.color(part.tone) : .clear, lineWidth: 2))
      .contentShape(RoundedRectangle(cornerRadius: 18))
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(part.title + (part.subtitle.map { ", " + $0 } ?? ""))
    .accessibilityValue(accessibleValue(part))
    .accessibilityHint("Shows this breakdown. Select again to show the full session.")
    .accessibilityAddTraits(selectedID == part.id ? .isSelected : [])
  }

  private func accessiblePartButton(_ part: SessionBreakdown.Part) -> some View {
    Button { select(part) } label: {
      VStack(alignment: .leading, spacing: 12) {
        Label(part.title, systemImage: selectedID == part.id ? "checkmark" : "circle.fill")
          .font(.headline)
        if let subtitle = part.subtitle { Text(subtitle).font(.subheadline) }
        Text("\(breakdown.value(for: part.amount)) \(breakdown.unit(for: part.amount)) · "
          + breakdown.share(of: part).formatted(.percent.precision(.fractionLength(0))))
          .font(.subheadline)
        shareBar(part)
      }
      .foregroundStyle(SessionPalette.ink(part.tone))
      .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      .padding(16)
      .background(SessionPalette.wash(part.tone), in: RoundedRectangle(cornerRadius: 18))
      .contentShape(RoundedRectangle(cornerRadius: 18))
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
      Capsule().fill(SessionPalette.color(part.tone).opacity(0.14))
        .overlay(alignment: .leading) {
          Capsule().fill(SessionPalette.color(part.tone)).frame(width: geometry.size.width * breakdown.share(of: part))
        }
    }.frame(height: 5).accessibilityHidden(true)
  }

  private func select(_ part: SessionBreakdown.Part) { selectedID = selectedID == part.id ? nil : part.id }

  private func accessibleValue(_ part: SessionBreakdown.Part) -> String {
    breakdown.spokenValue(for: part.amount) + ", "
      + breakdown.share(of: part).formatted(.percent.precision(.fractionLength(0))) + " of the planned session"
  }
}
