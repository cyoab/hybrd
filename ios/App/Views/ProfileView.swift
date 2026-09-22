import SwiftUI

struct ProfileView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var profile = TrainingProfile()
  @State private var weeklyDistance = ""
  @State private var loaded = false
  @State private var proposal: TrainingPlan?
  @State private var confirmDiscard = false
  @FocusState private var focusedField: Field?
  private enum Field: Hashable { case name, distance }
  private let weekdays = [(2, "Mon", "Monday"), (3, "Tue", "Tuesday"), (4, "Wed", "Wednesday"),
    (5, "Thu", "Thursday"), (6, "Fri", "Friday"), (7, "Sat", "Saturday"), (1, "Sun", "Sunday")]

  private var editedProfile: TrainingProfile? {
    guard let distance = TrainingProfile.parseWeeklyKilometers(weeklyDistance) else { return nil }
    var edited = profile
    edited.weeklyKilometers = distance
    return edited
  }

  private var hasChanges: Bool {
    loaded && (editedProfile != store.profile || profile != store.profile)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          identity
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 16, trailing: 0))
            .listRowBackground(Color.clear)
        }

        Section {
          TextField("Your name", text: $profile.name)
            .textContentType(.givenName)
            .focused($focusedField, equals: .name)
            .onSubmit { focusedField = nil }
            .submitLabel(.done)
            .accessibilityLabel("Your name")
        } header: { Text("What should we call you?") }

        Section {
          Picker("Running goal", systemImage: "figure.run", selection: $profile.runningGoal) {
            ForEach(RunningGoal.allCases) { Text($0.rawValue).tag($0) }
          }
          Picker("Strength goal", systemImage: "dumbbell", selection: $profile.strengthGoal) {
            ForEach(StrengthGoal.allCases) { Text($0.rawValue).tag($0) }
          }
          Picker("Focus", systemImage: "scope", selection: $profile.priority) {
            ForEach(TrainingPriority.allCases) { Text($0.rawValue).tag($0) }
          }
        } header: { Text("01 · Your direction") }

        Section {
          VStack(alignment: .leading, spacing: 12) {
            Label("Weekly running distance", systemImage: "figure.run").font(.subheadline.weight(.medium))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              TextField("24", text: $weeklyDistance)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .distance)
                .accessibilityLabel("Weekly running distance in kilometers")
                .accessibilityHint("Enter any distance from 3 to 150 kilometers.")
                .fixedSize(horizontal: false, vertical: true)
              Text("km / week").font(.subheadline).foregroundStyle(HybrdStyle.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
              .stroke(focusedField == .distance ? HybrdStyle.terra : HybrdStyle.line, lineWidth: 1))
            if TrainingProfile.parseWeeklyKilometers(weeklyDistance) == nil {
              Label("Enter a distance from 3 to 150 km.", systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(HybrdStyle.terraText)
            } else {
              Text("Tap the number to edit. Decimals welcome.")
                .font(.caption).foregroundStyle(HybrdStyle.muted)
            }
          }.padding(.vertical, 8)

          VStack(alignment: .leading, spacing: 12) {
            Text("Strength sessions / week").font(.subheadline.weight(.medium))
            Picker("Strength sessions per week", selection: $profile.strengthDays) {
              ForEach(1...4, id: \.self) { Text("\($0)").tag($0) }
            }.pickerStyle(.segmented)
          }.padding(.vertical, 8)

          Picker("Time per session", systemImage: "clock", selection: $profile.sessionMinutes) {
            ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0) minutes").tag($0) }
          }
        } header: { Text("02 · Your current rhythm") } footer: {
          Text("Use a recent, comfortable weekly distance. Your available days and session length may limit the distance in your starter block.")
        }

        Section {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 88 : 62))], spacing: 10) {
            ForEach(weekdays, id: \.0) { day, shortName, name in
              Toggle(isOn: Binding(
                get: { profile.availableDays.contains(day) },
                set: { enabled in
                  if enabled { profile.availableDays.insert(day) }
                  else { profile.availableDays.remove(day) }
                }
              )) {
                VStack(spacing: 8) {
                  Text(shortName).font(.subheadline.weight(.medium))
                  Image(systemName: profile.availableDays.contains(day) ? "checkmark" : "minus")
                    .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .padding(.vertical, 5)
                .foregroundStyle(profile.availableDays.contains(day) ? HybrdStyle.primaryButtonText : HybrdStyle.muted)
                .background(profile.availableDays.contains(day) ? HybrdStyle.primaryButton : HybrdStyle.field,
                  in: RoundedRectangle(cornerRadius: 16))
              }
              .toggleStyle(.button).buttonStyle(.plain)
              .accessibilityLabel(name)
            }
          }.padding(.vertical, 8)
        } header: {
          HStack {
            Text("03 · Make room for training")
            Spacer()
            Text("\(profile.availableDays.count) days")
          }
        } footer: {
          Text(profile.availableDays.count < 2
            ? "Choose at least two training days to continue."
            : "Choose days that work for you. We’ll keep at least one for running and fit strength into the remaining days.")
        }

        Section {
          NavigationLink { ProfileConnectionsView() } label: {
            Label("Devices & connections", systemImage: "applewatch")
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(HybrdStyle.background)
      .scrollDismissesKeyboard(.interactively)
      .navigationTitle("Athlete profile")
      .navigationBarTitleDisplayMode(.inline)
      .tint(HybrdStyle.ink)
      .safeAreaInset(edge: .bottom) {
        Button {
          focusedField = nil
          if let editedProfile { proposal = store.starterProposal(for: editedProfile) }
        } label: {
          Label("Review starter block", systemImage: "arrow.right")
        }
        .buttonStyle(HybrdPrimaryButtonStyle())
        .disabled(editedProfile?.validationMessage != nil || editedProfile == nil)
        .opacity(editedProfile?.validationMessage == nil && editedProfile != nil ? 1 : 0.45)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(HybrdStyle.surface)
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close", systemImage: "xmark") {
            if hasChanges { confirmDiscard = true } else { dismiss() }
          }.labelStyle(.iconOnly)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { focusedField = nil }
        }
      }
      .interactiveDismissDisabled(hasChanges)
      .confirmationDialog("Discard profile changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
        Button("Discard changes", role: .destructive) { dismiss() }
        Button("Keep editing", role: .cancel) {}
      }
      .onAppear {
        guard !loaded else { return }
        profile = store.profile
        weeklyDistance = profile.weeklyKilometers.formatted(.number.grouping(.never))
        loaded = true
      }
      .sheet(item: $proposal) { plan in
        StarterReviewView(proposal: plan) { dismiss() }
      }
    }
  }

  private var identity: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack(spacing: 18) {
        ZStack {
          Circle().stroke(HybrdStyle.line, lineWidth: 2)
          Circle().trim(from: 0.02, to: 0.29).stroke(HybrdStyle.terra, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            .rotationEffect(.degrees(-90))
          Circle().fill(HybrdStyle.obsidian).padding(7)
          Text(initials).font(.title2.weight(.medium)).foregroundStyle(.white)
        }
        .frame(width: 78, height: 78).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 7) {
          Eyebrow(text: profile.isSample ? "Make it yours" : "hybrd athlete")
          Text("Two goals.\nOne you.")
            .font(.system(.title, design: .rounded, weight: .semibold)).tracking(-0.7)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Text("A little about you. A plan that fits your life.")
        .font(.subheadline).foregroundStyle(HybrdStyle.muted)
    }
  }

  private var initials: String {
    let words = profile.name.split(whereSeparator: \.isWhitespace)
    return words.isEmpty ? "h" : words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
  }
}
