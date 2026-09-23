import SwiftUI

struct AthleteLevelsView: View {
  @Bindable var editor: AthleteProfileEditor

  var body: some View {
    Form {
      Section {
        ProfileSectionHero(eyebrow: L10n.text("Your experience"), title: L10n.text("Your own pace."),
          subtitle: L10n.text("Your running and lifting experience can be different. Set each at your own pace."),
          artwork: .experience, tone: .mint)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      Section {
        ExperienceDisciplineCard(title: L10n.text("Running"), artwork: .running, tone: .terra,
          selection: $editor.details.runningLevel)
          .modifier(ProfileTintedRow(tone: .terra))
      }
      Section {
        ExperienceDisciplineCard(title: L10n.text("Strength"), artwork: .strength, tone: .violet,
          selection: $editor.details.strengthLevel)
          .modifier(ProfileTintedRow(tone: .violet))
      } footer: {
        Text(L10n.text("These describe your experience, not a fitness score. You can update them as your training changes."))
      }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle(L10n.text("Experience")).navigationBarTitleDisplayMode(.inline)
  }
}

private struct ExperienceDisciplineCard: View {
  var title: String
  var artwork: ProfileIllustration.Artwork
  var tone: SessionBreakdown.Tone
  @Binding var selection: TrainingExperience?
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text(title).font(.system(.title2, design: .rounded, weight: .semibold))
          Text(selection?.detail ?? L10n.text("Your starting point"))
            .font(.subheadline).foregroundStyle(HybrdStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if !typeSize.isAccessibilitySize {
          ProfileIllustration(artwork: artwork).frame(width: 82, height: 76)
        }
      }
      Picker(L10n.text("Experience level"), selection: $selection) {
        Text(L10n.text("Not set")).tag(Optional<TrainingExperience>.none)
        ForEach(TrainingExperience.allCases) { Text($0.displayName).tag(Optional($0)) }
      }
      .pickerStyle(.menu).tint(SessionPalette.ink(tone))
    }
    .padding(.vertical, 8)
  }
}
