import SwiftUI

struct ProfileView: View {
  @Environment(TrainingStore.self) private var store
  @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
  @Environment(\.dismiss) private var dismiss
  @State private var editor: AthleteProfileEditor?
  @State private var confirmDiscard = false
  @State private var saveError: String?
  @State private var proposal: TrainingPlan?

  var body: some View {
    NavigationStack {
      Group {
        if let editor { profileForm(editor) }
        else { ProgressView("Opening profile…") }
      }
      .navigationTitle("Athlete profile")
      .navigationBarTitleDisplayMode(.inline)
      .tint(HybrdStyle.ink)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") {
            if editor?.hasChanges == true { confirmDiscard = true } else { dismiss() }
          }.labelStyle(.iconOnly)
        }
      }
      .interactiveDismissDisabled(editor?.hasChanges == true)
      .confirmationDialog("Discard profile changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
        Button("Discard changes", role: .destructive) { dismiss() }
        Button("Keep editing", role: .cancel) {}
      }
      .alert("Couldn’t save profile", isPresented: Binding(
        get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
        Button("OK") { saveError = nil }
      } message: { Text(saveError ?? "") }
      .onAppear { if editor == nil { editor = AthleteProfileEditor(profile: store.profile) } }
      .sheet(item: $proposal) { plan in
        StarterReviewView(proposal: plan) { dismiss() }
          .environment(\.trainingUnits, plan.profile.trainingUnits)
      }
    }
    // Apply here as well because the profile is a separate sheet presentation.
    .preferredColorScheme(appearance.colorScheme)
  }

  private func profileForm(_ editor: AthleteProfileEditor) -> some View {
    Form {
      Section {
        AthleteProfileHeader(profile: editor.assembledProfile)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }

      Section("Your foundation") {
        NavigationLink { AthleteInfoView(editor: editor) } label: {
          ProfileMenuRow(title: "About you", subtitle: "Name, age, height & weight", symbol: "person", tone: .terra)
        }
        NavigationLink { AthleteLevelsView(editor: editor) } label: {
          ProfileMenuRow(title: "Experience", subtitle: levelSummary(editor), symbol: "chart.bar", tone: .mint)
        }
        NavigationLink { AthleteHeartRateView(editor: editor) } label: {
          ProfileMenuRow(title: "Heart-rate zones", subtitle: editor.zones == nil ? "Set your personal BPM ranges" : "Five personal zones",
            symbol: "heart", tone: .terra)
        }
      }

      Section("Your benchmarks") {
        NavigationLink { RunningBestsView(editor: editor) } label: {
          ProfileMenuRow(title: "Running PRs", subtitle: recordCount(editor.assembledProfile.athlete?.runningBests.count ?? 0),
            symbol: "stopwatch", tone: .terra)
        }
        NavigationLink { StrengthBestsView(editor: editor) } label: {
          ProfileMenuRow(title: "Strength PRs", subtitle: recordCount(editor.details.strengthBests.count),
            symbol: "trophy", tone: .violet)
        }
      }

      Section("Make strength yours") {
        NavigationLink { MuscleFocusView(editor: editor) } label: {
          ProfileMenuRow(title: "Muscle focus", subtitle: editor.details.focusMuscles.isEmpty ? "Choose your focus areas" :
            MuscleGroup.allCases.filter { editor.details.focusMuscles.contains($0) }.map(\.title).joined(separator: ", "),
            symbol: "figure.strengthtraining.traditional", tone: .violet)
        }
        NavigationLink { GymSetupView(editor: editor) } label: {
          ProfileMenuRow(title: "Your gym", subtitle: editor.details.gymConfigured ?
            (editor.details.equipment.isEmpty ? "Bodyweight setup" : "\(editor.details.equipment.count) equipment types") : "Choose your available equipment",
            symbol: "dumbbell", tone: .violet)
        }
      }

      Section("Training & connections") {
        NavigationLink { TrainingPreferencesView(editor: editor) } label: {
          ProfileMenuRow(title: "Goals & weekly rhythm", subtitle: "Running, strength & availability", symbol: "calendar", tone: .gold)
        }
        NavigationLink { ProfileConnectionsView(editor: editor) } label: {
          ProfileMenuRow(title: "Health & connections", subtitle: "Apple Health, Strava & Watch", symbol: "heart.text.clipboard", tone: .mint)
        }
      }
      Section {
        Button("Review a new starter block", systemImage: "arrow.right") {
          proposal = store.starterProposal(for: editor.assembledProfile)
        }
        .disabled(editor.validationMessage != nil)
      } footer: {
        Text("Save your profile without changing your plan. Review a new block when you’re ready to apply your training preferences.")
      }

      ProfileUnitsSection(editor: editor)
      ProfileAppearanceSection(appearance: $appearance)
    }
    .environment(\.trainingUnits, editor.units)
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        if let error = editor.validationMessage {
          Text(error).font(.caption).foregroundStyle(HybrdStyle.terraText)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Button("Save profile") {
          if store.saveProfile(editor.assembledProfile, replacing: editor.original) { dismiss() }
          else { saveError = store.errorMessage; store.errorMessage = nil }
        }
        .buttonStyle(HybrdPrimaryButtonStyle())
        .disabled(!editor.hasChanges || editor.validationMessage != nil)
      }
      .padding(.horizontal, 20).padding(.vertical, 12).background(HybrdStyle.surface)
    }
  }

  private func recordCount(_ count: Int) -> String {
    count == 1 ? "1 personal best" : "\(count) personal bests"
  }

  private func levelSummary(_ editor: AthleteProfileEditor) -> String {
    let run = editor.details.runningLevel?.rawValue ?? "Not set"
    let lift = editor.details.strengthLevel?.rawValue ?? "Not set"
    return "Run: \(run) · Lift: \(lift)"
  }
}

private struct ProfileMenuRow: View {
  var title: String
  var subtitle: String
  var symbol: String
  var tone: SessionBreakdown.Tone

  var body: some View {
    HStack(spacing: 13) {
      Image(systemName: symbol).font(.title3)
        .foregroundStyle(SessionPalette.ink(tone))
        .frame(width: 44, height: 44)
        .background(SessionPalette.wash(tone), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.headline).foregroundStyle(HybrdStyle.ink)
        Text(subtitle).font(.caption).foregroundStyle(HybrdStyle.muted)
      }
      .padding(.vertical, 5)
    }
    .accessibilityElement(children: .combine)
  }
}
