import SwiftUI

struct OnboardingInformationView: View {
  var title: String
  var symbol: String
  var message: String
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Image(systemName: symbol).font(.system(size: 42)).foregroundStyle(HybrdStyle.terraText).accessibilityHidden(true)
          Text(title).font(.system(.title, design: .rounded, weight: .bold))
          Text(message).foregroundStyle(HybrdStyle.muted)
        }.padding(28).frame(maxWidth: 560).frame(maxWidth: .infinity, alignment: .leading)
      }.background { OnboardingBackdrop() }
        .toolbar { ToolbarItem(placement: .confirmationAction) {
          Button(L10n.text("Close"), systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
        } }
    }.presentationDetents([.medium, .large])
  }
}
