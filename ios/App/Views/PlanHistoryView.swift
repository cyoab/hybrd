import SwiftUI

struct PlanHistoryView: View {
  @Environment(TrainingStore.self) private var store
  var body: some View {
    List(Array(store.state.plans.enumerated()).reversed(), id: \.element.id) { index, plan in
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Version \(index + 1)").font(.headline)
          Spacer()
          if plan.id == store.plan.id { Text("Active").font(.caption.bold()).foregroundStyle(HybrdStyle.terraText) }
        }
        Text(plan.reason).font(.subheadline)
        Text(plan.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(HybrdStyle.muted)
      }.padding(.vertical, 6)
    }
    .navigationTitle("Plan history")
    .toolbar(.visible, for: .navigationBar)
  }
}
