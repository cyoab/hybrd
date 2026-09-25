import SwiftUI

struct CoachArtifactView: View {
  var artifact: BackendWire.AgentArtifact
  var stale: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(L10n.text("HYBRD · AI COACH")).font(.caption2.bold()).tracking(1).foregroundStyle(HybrdStyle.terraText)
      if stale { Text(L10n.text("This workout has changed since this analysis. Ask again for an updated review.")).font(.subheadline.weight(.semibold)) }
      Text(artifact.content).textSelection(.enabled)
      if !artifact.observations.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Text(L10n.text("What you recorded")).font(.headline)
          ForEach(Array(artifact.observations.enumerated()), id: \.offset) { _, observation in
            DisclosureGroup { Text(observation.metricRefs.joined(separator: " · ")).font(.caption).textSelection(.enabled) } label: { Text(observation.text) }
          }
        }
      }
      lines(L10n.text("What it means"), artifact.interpretations.map(\.text))
      lines(L10n.text("Keep in mind"), artifact.limitations)
      lines(L10n.text("Your next step"), artifact.recommendations)
      if !artifact.citations.isEmpty {
        DisclosureGroup(L10n.text("Sources")) {
          ForEach(Array(artifact.citations.enumerated()), id: \.offset) { _, citation in
            VStack(alignment: .leading, spacing: 6) {
              if let url = URL(string: citation.url), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil {
                Link(citation.title, destination: url).font(.subheadline.weight(.semibold))
              } else { Text(citation.title).font(.subheadline.weight(.semibold)) }
              Text(citation.claim).font(.caption)
              Text(citation.limitations).font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 8)
          }
        }
      }
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20)).tint(HybrdStyle.terraText)
  }
  @ViewBuilder private func lines(_ title: String, _ values: [String]) -> some View {
    if !values.isEmpty {
      VStack(alignment: .leading, spacing: 9) {
        Text(title).font(.headline)
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in Text(value).textSelection(.enabled) }
      }
    }
  }
}
