import SwiftUI

struct AthleteLevelsView: View {
  @Bindable var editor: AthleteProfileEditor

  var body: some View {
    Form {
      Section {
        ProfileSectionHero(eyebrow: "Your experience", title: "Your own pace.",
          subtitle: "Your running and lifting experience can be different. Set each at your own pace.",
          artwork: .experience, tone: .mint)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      Section {
        ExperienceDisciplineCard(title: "Running", artwork: .running, tone: .terra,
          selection: $editor.details.runningLevel)
          .modifier(ProfileTintedRow(tone: .terra))
      }
      Section {
        ExperienceDisciplineCard(title: "Strength", artwork: .strength, tone: .violet,
          selection: $editor.details.strengthLevel)
          .modifier(ProfileTintedRow(tone: .violet))
      } footer: {
        Text("These describe your experience, not a fitness score. You can update them as your training changes.")
      }
    }
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle("Experience").navigationBarTitleDisplayMode(.inline)
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
          Text(selection?.detail ?? "Your starting point")
            .font(.subheadline).foregroundStyle(HybrdStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if !typeSize.isAccessibilitySize {
          ProfileIllustration(artwork: artwork).frame(width: 82, height: 76)
        }
      }
      Picker("Experience level", selection: $selection) {
        Text("Not set").tag(Optional<TrainingExperience>.none)
        ForEach(TrainingExperience.allCases) { Text($0.rawValue).tag(Optional($0)) }
      }
      .pickerStyle(.menu).tint(SessionPalette.ink(tone))
    }
    .padding(.vertical, 8)
  }
}
