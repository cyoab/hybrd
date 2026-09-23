import SwiftUI
import MapKit

struct RunSummaryView: View {
  @Environment(\.trainingUnits) private var units
  var run: RunRecording
  private var routes: [[CLLocationCoordinate2D]] {
    var groups: [[CLLocationCoordinate2D]] = []
    for point in run.route {
      if point.startsSegment || groups.isEmpty { groups.append([]) }
      groups[groups.count - 1].append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
    }
    return groups
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Eyebrow(text: L10n.text("The work is yours"))
      Text(L10n.text("Run complete.")).font(.system(.largeTitle, design: .rounded, weight: .semibold))
      Text(run.workout.localizedTitle).font(.title3)
      if !run.route.isEmpty {
        Map {
          ForEach(Array(routes.enumerated()), id: \.offset) { _, coordinates in
            MapPolyline(coordinates: coordinates).stroke(HybrdStyle.terra, lineWidth: 5)
          }
        }.mapStyle(.standard(elevation: .flat)).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 26))
          .accessibilityLabel(L10n.text("Recorded route. Gaps are left disconnected."))
      }
      VStack(spacing: 14) {
        LabeledContent(L10n.text("Distance"), value: units.distanceText(run.meters, decimals: 2))
        LabeledContent(L10n.text("Active time"), value: RunRecording.clock(run.elapsed))
        LabeledContent(L10n.text("Average pace"), value: units.paceText(run.averagePace))
        if let bpm = run.averageHeartRate { LabeledContent(L10n.text("Average heart rate"), value: L10n.text("\(Int(bpm.rounded())) bpm")) }
        if let bpm = run.maximumHeartRate { LabeledContent(L10n.text("Maximum heart rate"), value: L10n.text("\(Int(bpm.rounded())) bpm")) }
      }.font(.headline).padding(20).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 24))
      if let message = run.healthSaveMessage { Label(L10n.content(message), systemImage: "heart").font(.subheadline).foregroundStyle(HybrdStyle.muted) }
      if let message = run.recoveryMessage { Text(L10n.content(message)).font(.caption).foregroundStyle(HybrdStyle.muted) }
      if !run.laps.isEmpty {
        Text(L10n.text("Splits & laps")).font(.title3.bold())
        ForEach(run.laps) { lap in
          HStack {
            VStack(alignment: .leading, spacing: 4) { Text(units.lapTitle(lap)); Text(units.distanceText(lap.meters, decimals: 2)).font(.caption).foregroundStyle(HybrdStyle.muted) }
            Spacer()
            Text(RunRecording.clock(lap.seconds)).monospacedDigit()
            Text(units.paceText(lap.pace)).font(.caption).foregroundStyle(HybrdStyle.muted)
          }.padding(.vertical, 4)
          Divider()
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
