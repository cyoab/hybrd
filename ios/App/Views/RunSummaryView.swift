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
      Eyebrow(text: "The work is yours")
      Text("Run complete.").font(.system(.largeTitle, design: .rounded, weight: .semibold))
      Text(run.workout.title).font(.title3)
      if !run.route.isEmpty {
        Map {
          ForEach(Array(routes.enumerated()), id: \.offset) { _, coordinates in
            MapPolyline(coordinates: coordinates).stroke(HybrdStyle.terra, lineWidth: 5)
          }
        }.mapStyle(.standard(elevation: .flat)).frame(height: 220).clipShape(RoundedRectangle(cornerRadius: 26))
          .accessibilityLabel("Recorded route. Gaps are left disconnected.")
      }
      VStack(spacing: 14) {
        LabeledContent("Distance", value: units.distanceText(run.meters, decimals: 2))
        LabeledContent("Active time", value: RunRecording.clock(run.elapsed))
        LabeledContent("Average pace", value: units.paceText(run.averagePace))
        if let bpm = run.averageHeartRate { LabeledContent("Average heart rate", value: "\(Int(bpm.rounded())) bpm") }
        if let bpm = run.maximumHeartRate { LabeledContent("Maximum heart rate", value: "\(Int(bpm.rounded())) bpm") }
      }.font(.headline).padding(20).background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 24))
      if let message = run.healthSaveMessage { Label(message, systemImage: "heart").font(.subheadline).foregroundStyle(HybrdStyle.muted) }
      if let message = run.recoveryMessage { Text(message).font(.caption).foregroundStyle(HybrdStyle.muted) }
      if !run.laps.isEmpty {
        Text("Splits & laps").font(.title3.bold())
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
