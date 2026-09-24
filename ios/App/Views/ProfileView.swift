import SwiftUI

struct ProfileView: View {
  @Environment(BackendAppController.self) private var backend
  @Environment(TrainingStore.self) private var store
  @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
  @Environment(\.dismiss) private var dismiss
  @State private var editor: AthleteProfileEditor?
  @State private var confirmDiscard = false
  @State private var saveError: String?
  @State private var proposal: TrainingPlan?
  @State private var showOnboarding = false

  var body: some View {
    NavigationStack {
      Group {
        if let editor { profileForm(editor) }
        else { ProgressView(L10n.text("Opening profile…")) }
      }
      .navigationTitle(L10n.text("Athlete profile"))
      .navigationBarTitleDisplayMode(.inline)
      .tint(HybrdStyle.ink)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(L10n.text("Close"), systemImage: "xmark") {
            if editor?.hasChanges == true { confirmDiscard = true } else { dismiss() }
          }.labelStyle(.iconOnly)
        }
      }
      .interactiveDismissDisabled(editor?.hasChanges == true)
      .confirmationDialog(L10n.text("Discard profile changes?"), isPresented: $confirmDiscard, titleVisibility: .visible) {
        Button(L10n.text("Discard changes"), role: .destructive) { dismiss() }
        Button(L10n.text("Keep editing"), role: .cancel) {}
      }
      .alert(L10n.text("Couldn’t save profile"), isPresented: Binding(
        get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
        Button(L10n.text("OK")) { saveError = nil }
      } message: { Text(saveError ?? "") }
      .onAppear { if editor == nil { editor = AthleteProfileEditor(profile: store.profile) } }
      .sheet(item: $proposal) { plan in
        StarterReviewView(proposal: plan) { dismiss() }
          .environment(\.trainingUnits, plan.profile.trainingUnits)
      }
    }
    // Apply here as well because the profile is a separate sheet presentation.
    .preferredColorScheme(appearance.colorScheme)
    .fullScreenCover(isPresented: $showOnboarding) {
      OnboardingEntryView { showOnboarding = false }
        .preferredColorScheme(appearance.colorScheme)
    }
  }

  private func profileForm(_ editor: AthleteProfileEditor) -> some View {
    Form {
      Section {
        AthleteProfileHeader(profile: editor.assembledProfile)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }

      Section(L10n.text("Your foundation")) {
        NavigationLink { AthleteInfoView(editor: editor) } label: {
          ProfileMenuRow(title: L10n.text("About you"), subtitle: L10n.text("Name, age, height & weight"), symbol: "person", tone: .terra)
        }
        NavigationLink { AthleteLevelsView(editor: editor) } label: {
          ProfileMenuRow(title: L10n.text("Experience"), subtitle: levelSummary(editor), symbol: "chart.bar", tone: .mint)
        }
        NavigationLink { AthleteHeartRateView(editor: editor) } label: {
          ProfileMenuRow(title: L10n.text("Heart-rate zones"), subtitle: editor.zones == nil ? L10n.text("Set your personal BPM ranges") : L10n.text("Five personal zones"),
            symbol: "heart", tone: .terra)
        }
      }

      Section(L10n.text("Your benchmarks")) {
        NavigationLink { RunningBestsView(editor: editor) } label: {
          ProfileMenuRow(title: L10n.text("Running PRs"), subtitle: recordCount(editor.assembledProfile.athlete?.runningBests.count ?? 0),
            symbol: "stopwatch", tone: .terra)
        }
        NavigationLink { StrengthBestsView(editor: editor) } label: {
          ProfileMenuRow(title: L10n.text("Strength PRs"), subtitle: recordCount(editor.details.strengthBests.count),
            symbol: "trophy", tone: .violet)
        }
      }

      Section(L10n.text("Make strength yours")) {
        NavigationLink { MuscleFocusView(editor: editor) } label: {
          ProfileMenuRow(title: L10n.text("Muscle focus"), subtitle: editor.details.focusMuscles.isEmpty ? L10n.text("Choose your focus areas") :
            MuscleGroup.allCases.filter { editor.details.focusMuscles.contains($0) }.map(\.title).joined(separator: ", "),
            symbol: "figure.strengthtraining.traditional", tone: .violet)
        }
        NavigationLink { GymSetupView(editor: editor) } label: {
          ProfileMenuRow(title: L10n.text("Your gym"), subtitle: editor.details.gymConfigured ?
            (editor.details.equipment.isEmpty ? L10n.text("Bodyweight setup") : L10n.text("\(editor.details.equipment.count) equipment types")) : L10n.text("Choose your available equipment"),
            symbol: "dumbbell", tone: .violet)
        }
      }

      Section(L10n.text("Training & connections")) {
        NavigationLink { TrainingPreferencesView(editor: editor) } label: {
          ProfileMenuRow(title: L10n.text("Goals & weekly rhythm"), subtitle: L10n.text("Running, strength & availability"), symbol: "calendar", tone: .gold)
        }
        if !backend.connected { NavigationLink { ProfileConnectionsView(editor: editor) } label: {
          ProfileMenuRow(title: L10n.text("Health & connections"), subtitle: L10n.text("Apple Health, Strava & Watch"), symbol: "heart.text.clipboard", tone: .mint)
        } }
      }
      Section {
        Button(L10n.text("Review a new starter block"), systemImage: "arrow.right") {
          proposal = store.starterProposal(for: editor.assembledProfile)
        }
        .disabled(editor.validationMessage != nil || !editor.assembledProfile.supportsStarterPlan)
      } footer: {
        if !editor.assembledProfile.supportsStarterPlan { Text(L10n.text("Your baseline is saved as entered. Starter plans currently support 3–150 km per week.")) }
        Text(L10n.text("Save your profile without changing your plan. Review a new block when you’re ready to apply your training preferences."))
      }

      if !backend.connected { Section {
        Button(L10n.text("Try sign-up & onboarding"), systemImage: "sparkles") { showOnboarding = true }
      } footer: {
        Text(L10n.text("Preview the new athlete journey and membership screen. No account changes or charges."))
      } }

      Section {
        Button(backend.connected ? L10n.text("Account & sync") : L10n.text("Connect with email")) {
          dismiss()
          if backend.connected { backend.showAccount = true } else { backend.showAuthentication = true }
        }
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
        Button(L10n.text("Save profile")) {
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
    L10n.text("\(count) personal bests")
  }

  private func levelSummary(_ editor: AthleteProfileEditor) -> String {
    let run = editor.details.runningLevel?.displayName ?? L10n.text("Not set")
    let lift = editor.details.strengthLevel?.displayName ?? L10n.text("Not set")
    return L10n.text("Run: \(run) · Lift: \(lift)")
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
