import SwiftUI

struct WorkoutLoggerView: View {
  @Environment(\.trainingUnits) private var units
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicType
  @State var draft: WorkoutDraft
  @State private var finished = false
  @State private var showFinish = false
  @State private var completionFeedback = 0
  @State private var showSessionNotes = false
  @State private var exerciseIndex = 0
  @State private var restMessage: String?
  @AppStorage("hybrd.restAlerts") private var restAlerts = false
  private var completedSets: Int { draft.sets.filter(\.isComplete).count }

  var body: some View {
    NavigationStack {
      Group {
        if draft.workout.kind == .run {
          runForm
        } else {
          strengthContent
        }
      }
      .background(HybrdStyle.background)
      .navigationTitle(draft.workout.kind == .run ? L10n.text("Log run") : L10n.text("Workout"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(L10n.text("Save for later"), systemImage: "chevron.down") { pauseAndClose() }
            .labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(L10n.text("Finish")) { showFinish = true }
            .fontWeight(.semibold)
            .disabled(!draft.canFinish)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button(L10n.text("Done")) { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if draft.workout.kind == .strength {
          restBar
        }
      }
      .onAppear {
        if let index = draft.workout.exercises.firstIndex(where: { exercise in
          draft.sets.contains { $0.exerciseName == exercise.name && !$0.isComplete }
        }) { exerciseIndex = index }
        draft.resume()
        store.saveDraft(draft)
        if restAlerts { Task {
          restAlerts = await RestReminder.requestPermission()
          if !restAlerts { restMessage = L10n.text("Rest alerts are off in Settings.") }
          RestReminder.schedule(draft.rest, workoutID: draft.id, enabled: restAlerts)
        } }
      }
      .onDisappear {
        if !finished { draft.pause(); store.saveDraft(draft) }
      }
      .onChange(of: draft) { _, newValue in
        if !finished { store.saveDraft(newValue) }
      }
      .onChange(of: draft.rest) { _, value in
        RestReminder.schedule(value, workoutID: draft.id, enabled: restAlerts)
      }
      .sensoryFeedback(.success, trigger: completionFeedback)
      .sheet(isPresented: $showSessionNotes) { notesSheet }
      .confirmationDialog(L10n.text("Finish this session?"), isPresented: $showFinish, titleVisibility: .visible) {
        Button(L10n.text("Save completed work")) {
          draft.pause()
          if store.finish(draft) {
            finished = true
            draft.rest = nil
            RestReminder.schedule(nil, workoutID: draft.id, enabled: false)
            dismiss()
          }
        }
      } message: {
        Text(draft.workout.kind == .strength ? L10n.text("\(completedSets) sets will be saved. Unchecked sets won’t be recorded, and your prescription stays unchanged.") : L10n.text("Your actual distance, time, effort, and notes will be saved."))
      }
    }
    .tint(HybrdStyle.terraText)
  }

  private var strengthContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        workoutHeader
        if draft.workout.exercises.indices.contains(exerciseIndex) {
          Picker(L10n.text("Current exercise"), selection: $exerciseIndex) {
            ForEach(Array(draft.workout.exercises.enumerated()), id: \.element.id) { index, exercise in
              Text("\(index + 1). " + exercise.localizedName).tag(index)
            }
          }.pickerStyle(.menu).labelsHidden().tint(SessionPalette.ink(.violet))
          let exercise = draft.workout.exercises[exerciseIndex]
          exerciseCard(exercise)
          if exerciseIndex + 1 < draft.workout.exercises.count {
            Button(L10n.text("Next exercise"), systemImage: "arrow.right") { exerciseIndex += 1 }
              .buttonStyle(.bordered).frame(maxWidth: .infinity)
          }
        }
        Button { showSessionNotes = true } label: {
          HStack {
            Label(draft.notes.isEmpty ? L10n.text("Effort & session notes") : L10n.text("Edit effort & notes"), systemImage: "square.and.pencil")
            Spacer()
            Text(L10n.text("RPE \(draft.effort)")).foregroundStyle(HybrdStyle.muted)
          }
          .font(.subheadline).padding(17)
          .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
        if let validation = draft.validationMessage(in: units), completedSets > 0 {
          Text(validation).font(.caption).foregroundStyle(.red)
        }
        Button(L10n.text("Finish workout")) { showFinish = true }
          .buttonStyle(HybrdPrimaryButtonStyle()).disabled(!draft.canFinish)
        Text(L10n.text("Check only the sets you performed. Press and hold a row to remove it from your log."))
          .font(.caption).foregroundStyle(HybrdStyle.muted)
      }
      .padding(.horizontal, 16).padding(.vertical, 18)
      .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private var workoutHeader: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(draft.workout.localizedTitle).font(.system(.title, design: .rounded, weight: .semibold)).tracking(-0.7)
      TimelineView(.periodic(from: .now, by: 1)) { context in
        HStack(alignment: .top, spacing: 18) {
          smallMetric(value: clock(draft.activeSeconds(at: context.date)), label: draft.runningSince == nil ? L10n.text("PAUSED") : L10n.text("DURATION"))
          Spacer(minLength: 0)
          smallMetric(value: units.weightText(volume), label: L10n.text("VOLUME"))
          Spacer(minLength: 0)
          smallMetric(value: "\(completedSets)", label: L10n.text("SETS"))
          Button(draft.runningSince == nil ? L10n.text("Resume workout") : L10n.text("Pause workout"),
            systemImage: draft.runningSince == nil ? "play.fill" : "pause.fill") {
              if draft.runningSince == nil { draft.resume() } else { draft.pause() }
            }
            .labelStyle(.iconOnly).frame(width: 44, height: 44)
            .background(HybrdStyle.field, in: Circle())
        }
      }
      ProgressView(value: Double(completedSets), total: Double(max(1, draft.sets.count)))
        .tint(HybrdStyle.terra)
        .accessibilityLabel(L10n.text("\(completedSets) of \(draft.sets.count) sets completed"))
    }
  }

  private var volume: Double {
    draft.sets.filter(\.isComplete).reduce(0) { $0 + $1.kilograms * Double($1.reps) }
  }

  private func smallMetric(value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(HybrdStyle.muted)
      Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
    }.accessibilityElement(children: .combine)
  }

  private func exerciseCard(_ exercise: ExercisePrescription) -> some View {
    let sets = draft.sets.filter { $0.exerciseName == exercise.name }
    let previous = store.previousSets(for: exercise.name)
    return VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .top, spacing: 12) {
        Image("SessionDumbbell").resizable().scaledToFit().frame(width: 62, height: 62)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
          Text(exercise.localizedName).font(.system(.title2, design: .rounded, weight: .semibold)).foregroundStyle(SessionPalette.ink(.violet))
          Text(L10n.text("\(exercise.sets.count) prescribed sets · \(exercise.sets.first?.reps ?? 0) reps · \(exercise.sets.first?.targetRIR ?? 3) target RIR"))
            .font(.caption).foregroundStyle(HybrdStyle.muted)
        }
        Spacer(minLength: 0)
      }
      Text(exercise.localizedNote).font(.caption).foregroundStyle(HybrdStyle.muted)
      Button(L10n.text("Rest timer: \(exercise.restSeconds) sec"), systemImage: "timer") {
        beginRest(exercise)
      }.font(.caption.weight(.medium)).buttonStyle(.plain).foregroundStyle(HybrdStyle.terraText)

      if !dynamicType.isAccessibilitySize {
        HStack(spacing: 8) {
          Text(L10n.text("SET")).frame(width: 22)
          Text(units.weight.symbol.uppercased()).frame(maxWidth: .infinity)
          Text(L10n.text("REPS")).frame(maxWidth: .infinity)
          Text(L10n.text("RIR")).frame(width: 48)
          Image(systemName: "checkmark").frame(width: 44)
        }
        .font(.system(size: 9, weight: .medium)).foregroundStyle(HybrdStyle.muted)
        .padding(.horizontal, 10).accessibilityHidden(true)
      }
      VStack(spacing: 2) {
        ForEach(Array(sets.enumerated()), id: \.element.id) { position, set in
          StrengthSetRow(loggedSet: binding(for: set), number: position + 1,
            previous: previous.indices.contains(position) ? previous[position] : nil) {
              draft.sets.removeAll { $0.id == set.id }
            }
            .onChange(of: set.isComplete) { _, complete in
              if complete {
                completionFeedback += 1
                beginRest(exercise)
              }
            }
        }
      }
      Button {
        draft.addSet(for: exercise)
      } label: {
        Label(L10n.text("Add set"), systemImage: "plus")
          .font(.subheadline.weight(.medium))
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 10))
      }.buttonStyle(.plain)
    }
    .padding(14)
    .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(SessionPalette.violet.opacity(0.2)))
  }

  private func binding(for set: LoggedSet) -> Binding<LoggedSet> {
    Binding(get: { draft.sets.first { $0.id == set.id } ?? set }, set: { updated in
      guard let index = draft.sets.firstIndex(where: { $0.id == set.id }) else { return }
      draft.sets[index] = updated
    })
  }

  private func beginRest(_ exercise: ExercisePrescription) {
    draft.rest = StrengthRestTimer(duration: Double(exercise.restSeconds),
      endsAt: Date().addingTimeInterval(Double(exercise.restSeconds)), exerciseName: exercise.name)
  }

  private var restBar: some View {
    Group {
      if let rest = draft.rest {
        TimelineView(.periodic(from: .now, by: 1)) { context in
          let remaining = rest.remaining(at: context.date)
          VStack(alignment: .leading, spacing: 10) {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(remaining > 0 ? L10n.text("REST & RESET") : L10n.text("READY WHEN YOU ARE")).font(.caption2.weight(.semibold)).tracking(1)
                Text(remaining > 0 ? clock(ceil(remaining)) : L10n.text("Next set")).font(.system(.title2, design: .rounded, weight: .semibold)).monospacedDigit()
              }
              Spacer()
              Button(L10n.text("Add 15 seconds"), systemImage: "plus") { draft.rest?.extend(by: 15) }.labelStyle(.iconOnly).frame(width: 44, height: 44)
              Button(remaining > 0 ? L10n.text("Skip rest") : L10n.text("Done"), systemImage: "forward.end.fill") { draft.rest = nil }.labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            ProgressView(value: min(1, remaining / max(1, rest.duration))).tint(SessionPalette.violet)
              .accessibilityLabel(L10n.text("Rest time remaining"))
            if !restAlerts {
              Button(L10n.text("Enable rest alerts"), systemImage: "bell") {
                Task {
                  restAlerts = await RestReminder.requestPermission()
                  restMessage = restAlerts ? nil : L10n.text("Rest alerts are off. You can allow notifications for hybrd in Settings.")
                  RestReminder.schedule(draft.rest, workoutID: draft.id, enabled: restAlerts)
                }
              }.font(.caption)
            }
            if let restMessage { Text(restMessage).font(.caption2) }
          }.padding(16).background(SessionPalette.wash(.violet))
            .sensoryFeedback(.success, trigger: remaining <= 0)
        }
      }
    }
  }

  private var runForm: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text(draft.workout.localizedTitle).font(.title2.weight(.semibold))
          Text(L10n.text("Prescribed: ") + units.summary(draft.workout)).font(.subheadline).foregroundStyle(HybrdStyle.muted)
          if let zone = draft.workout.primaryHeartRateZone { RunZoneBadge(zone: zone) }
          Text(L10n.text("Enter the run you completed.")).font(.subheadline)
        }.padding(.vertical, 8)
      }
      Section(L10n.text("Actual results")) {
        LabeledContent(L10n.text("Distance · ") + units.distance.symbol) {
          TextField("0.0", value: Binding(get: { units.distance.value(fromMeters: draft.distanceKilometers * 1_000) }, set: { draft.distanceKilometers = units.distance.meters(from: $0) / 1_000 }), format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            .accessibilityLabel(L10n.text("Actual distance in ") + units.distance.title.lowercased())
        }
        LabeledContent(L10n.text("Duration · min")) {
          TextField("0", value: $draft.durationMinutes, format: .number)
            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            .accessibilityLabel(L10n.text("Actual duration in minutes"))
        }
        if draft.distanceKilometers > 0 && draft.durationMinutes > 0 {
          LabeledContent(L10n.text("Average pace"), value: paceLabel)
        }
      }
      effortSection
      Section {
        Button(L10n.text("Save run")) { showFinish = true }.fontWeight(.semibold).disabled(!draft.canFinish)
      } footer: {
        Text(L10n.text("Use Start run for GPS recording. This form logs a run you already completed."))
      }
    }
    .scrollContentBackground(.hidden)
  }

  private var paceLabel: String {
    guard draft.distanceKilometers.isFinite, (0.001...500).contains(draft.distanceKilometers), (1...2_880).contains(draft.durationMinutes) else { return "—" }
    return units.paceText(Double(draft.durationMinutes * 60) / draft.distanceKilometers)
  }

  private var effortSection: some View {
    Section(L10n.text("How did it feel?")) {
      LabeledContent(L10n.text("How it felt"), value: "\(draft.effort) / 10")
      Slider(value: Binding(get: { Double(draft.effort) }, set: { draft.effort = Int($0) }), in: 1...10, step: 1) {
        Text(L10n.text("Session effort"))
      } minimumValueLabel: {
        Text(L10n.text("Easy")).font(.caption)
      } maximumValueLabel: {
        Text(L10n.text("Max")).font(.caption)
      }
      TextField(L10n.text("Session notes"), text: $draft.notes, axis: .vertical).lineLimit(3...6)
    }
  }

  private var notesSheet: some View {
    NavigationStack {
      Form {
        effortSection
        Section(L10n.text("Rest timer")) {
          Toggle(L10n.text("Rest alerts"), isOn: $restAlerts).onChange(of: restAlerts) { _, enabled in
            if enabled { Task { restAlerts = await RestReminder.requestPermission(); RestReminder.schedule(draft.rest, workoutID: draft.id, enabled: restAlerts) } }
            else { RestReminder.schedule(nil, workoutID: draft.id, enabled: false) }
          }
          Text(L10n.text("RIR means reps in reserve: how many more good repetitions you could have completed. Leave it blank when you’re unsure.")).font(.caption)
        }
      }
        .navigationTitle(L10n.text("Effort & notes")).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { showSessionNotes = false } } }
    }.presentationDetents([.medium, .large])
  }

  private func pauseAndClose() {
    draft.pause()
    store.saveDraft(draft)
    dismiss()
  }

  private func clock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    return "\(total / 60):\(String(format: "%02d", total % 60))"
  }
}
