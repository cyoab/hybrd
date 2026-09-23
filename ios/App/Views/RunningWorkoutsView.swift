import SwiftUI

struct RunningWorkoutsView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  var selectedDate: Date
  var onAdded: (Date) -> Void

  private var columns: [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: L10n.text("A run for your rhythm"))
            Text(L10n.text("Find your next run."))
              .font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1)
            Text(L10n.text("Choose a session, explore its HR targets, and find a place for it in your week."))
              .font(.subheadline).foregroundStyle(HybrdStyle.muted)
          }
          LazyVGrid(columns: columns, spacing: 12) {
            ForEach(RunWorkoutTemplate.allCases) { template in
              NavigationLink {
                RunWorkoutPreviewView(template: template, selectedDate: selectedDate, plan: store.plan, onAdded: onAdded)
              } label: {
                RunWorkoutCard(template: template)
              }
              .buttonStyle(.plain)
              .accessibilityHint(L10n.text("Review workout steps and choose a date"))
            }
          }
          Text(L10n.text("Card colors identify the run type. The zone colors inside a session show its heart-rate targets."))
            .font(.caption).foregroundStyle(HybrdStyle.muted)
        }
        .padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
      }
      .background(HybrdStyle.background)
      .navigationTitle(L10n.text("Running workouts"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Close"), systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
        }
      }
    }
    .tint(HybrdStyle.ink)
  }
}

private struct RunWorkoutCard: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var template: RunWorkoutTemplate

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack {
        Image(systemName: template.type.symbol).font(.title2)
        Spacer(minLength: 0)
        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
      }.accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 5) {
        Text(template.type.title).font(.headline)
        if typeSize.isAccessibilitySize {
          Text(template.localizedTitle).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        } else {
          Text(template.localizedTitle).font(.subheadline).lineLimit(2, reservesSpace: true)
        }
      }
      RunRhythmView(segments: template.segments, type: template.type)
      Text(L10n.text("\(template.minutes) min")).font(.caption.weight(.semibold)).monospacedDigit()
    }
    .foregroundStyle(RunPalette.ink(template.type))
    .padding(17).frame(maxWidth: .infinity, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 24).fill(LinearGradient(
        colors: [RunPalette.top(template.type), RunPalette.wash(template.type)],
        startPoint: .topLeading, endPoint: .bottomTrailing))
    }
    .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(RunPalette.color(template.type).opacity(0.2)))
    .contentShape(RoundedRectangle(cornerRadius: 24))
    .accessibilityElement(children: .combine)
  }
}
