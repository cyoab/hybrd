import SwiftUI

struct WorkoutLoggerView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicType
  @State var draft: WorkoutDraft
  @State private var finished = false
  @State private var showFinish = false
  @State private var completionFeedback = 0
  @State private var showSessionNotes = false
  @AppStorage("hybrd.restEnd") private var restEnd = 0.0
  @AppStorage("hybrd.restWorkout") private var restWorkout = ""
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
      .navigationTitle(draft.workout.kind == .run ? "Log run" : "Workout")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Save for later", systemImage: "chevron.down") { pauseAndClose() }
            .labelStyle(.iconOnly)
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Finish") { showFinish = true }
            .fontWeight(.semibold)
            .disabled(!draft.canFinish)
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if draft.workout.kind == .strength {
          restBar
        }
      }
      .onAppear {
        if restWorkout != draft.id.uuidString { restEnd = 0; restWorkout = draft.id.uuidString }
        draft.resume()
        store.saveDraft(draft)
      }
      .onDisappear {
        if !finished { draft.pause(); store.saveDraft(draft) }
      }
      .onChange(of: draft) { _, newValue in
        if !finished { store.saveDraft(newValue) }
      }
      .sensoryFeedback(.success, trigger: completionFeedback)
      .sheet(isPresented: $showSessionNotes) { notesSheet }
      .confirmationDialog("Finish this session?", isPresented: $showFinish, titleVisibility: .visible) {
        Button("Save completed work") {
          draft.pause()
          if store.finish(draft) {
            finished = true
            restEnd = 0
            dismiss()
          }
        }
      } message: {
        Text(draft.workout.kind == .strength ? "\(completedSets) sets will be saved. Unchecked sets won’t be recorded, and your prescription stays unchanged." : "Your actual distance, time, effort, and notes will be saved.")
      }
    }
    .tint(HybrdStyle.terraText)
  }

  private var strengthContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        workoutHeader
        ForEach(draft.workout.exercises) { exercise in
          exerciseCard(exercise)
        }
        Button { showSessionNotes = true } label: {
          HStack {
            Label(draft.notes.isEmpty ? "Effort & session notes" : "Edit effort & notes", systemImage: "square.and.pencil")
            Spacer()
            Text("RPE \(draft.effort)").foregroundStyle(HybrdStyle.muted)
          }
          .font(.subheadline).padding(17)
          .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
        if let validation = draft.validationMessage, completedSets > 0 {
          Text(validation).font(.caption).foregroundStyle(.red)
        }
        Button("Finish workout") { showFinish = true }
          .buttonStyle(HybrdPrimaryButtonStyle()).disabled(!draft.canFinish)
        Text("Check only the sets you performed. Press and hold a row to remove it from your log.")
          .font(.caption).foregroundStyle(HybrdStyle.muted)
      }
      .padding(.horizontal, 16).padding(.vertical, 18)
      .frame(maxWidth: 760).frame(maxWidth: .infinity)
    }
    .scrollDismissesKeyboard(.interactively)
  }

  private var workoutHeader: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(draft.workout.title).font(.system(.title, design: .rounded, weight: .semibold)).tracking(-0.7)
      TimelineView(.periodic(from: .now, by: 1)) { context in
        HStack(alignment: .top, spacing: 18) {
          smallMetric(value: clock(draft.activeSeconds(at: context.date)), label: draft.runningSince == nil ? "PAUSED" : "DURATION")
          Spacer(minLength: 0)
          smallMetric(value: volume.formatted(.number.precision(.fractionLength(0...1))) + " kg", label: "VOLUME")
          Spacer(minLength: 0)
          smallMetric(value: "\(completedSets)", label: "SETS")
          Button(draft.runningSince == nil ? "Resume workout" : "Pause workout",
            systemImage: draft.runningSince == nil ? "play.fill" : "pause.fill") {
              if draft.runningSince == nil { draft.resume() } else { draft.pause() }
            }
            .labelStyle(.iconOnly).frame(width: 44, height: 44)
            .background(HybrdStyle.field, in: Circle())
        }
      }
      ProgressView(value: Double(completedSets), total: Double(max(1, draft.sets.count)))
        .tint(HybrdStyle.terra)
        .accessibilityLabel("\(completedSets) of \(draft.sets.count) sets completed")
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
        Image(systemName: "dumbbell")
          .font(.title3).frame(width: 42, height: 42)
          .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 12))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 5) {
          Text(exercise.name).font(.headline).foregroundStyle(HybrdStyle.terraText)
          Text("\(exercise.sets.count) prescribed sets · \(exercise.sets.first?.reps ?? 0) reps · 3 RIR")
            .font(.caption).foregroundStyle(HybrdStyle.muted)
        }
        Spacer(minLength: 0)
      }
      Text(exercise.note).font(.caption).foregroundStyle(HybrdStyle.muted)
      Button("Rest timer: \(exercise.restSeconds) sec", systemImage: "timer") {
        restEnd = Date().addingTimeInterval(Double(exercise.restSeconds)).timeIntervalSince1970
      }.font(.caption.weight(.medium)).buttonStyle(.plain).foregroundStyle(HybrdStyle.terraText)

      if !dynamicType.isAccessibilitySize {
        HStack(spacing: 8) {
          Text("SET").frame(width: 24)
          Text("PREVIOUS").frame(width: 70)
          Text("KG").frame(maxWidth: .infinity)
          Text("REPS").frame(maxWidth: .infinity)
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
                restEnd = Date().addingTimeInterval(Double(exercise.restSeconds)).timeIntervalSince1970
              }
            }
        }
      }
      Button {
        draft.addSet(for: exercise)
      } label: {
        Label("Add set", systemImage: "plus")
          .font(.subheadline.weight(.medium))
          .frame(maxWidth: .infinity, minHeight: 44)
          .background(HybrdStyle.field, in: RoundedRectangle(cornerRadius: 10))
      }.buttonStyle(.plain)
    }
    .padding(14)
    .background(HybrdStyle.surface, in: RoundedRectangle(cornerRadius: 20))
    .overlay(RoundedRectangle(cornerRadius: 20).stroke(HybrdStyle.line))
  }

  private func binding(for set: LoggedSet) -> Binding<LoggedSet> {
    Binding(get: { draft.sets.first { $0.id == set.id } ?? set }, set: { updated in
      guard let index = draft.sets.firstIndex(where: { $0.id == set.id }) else { return }
      draft.sets[index] = updated
    })
  }

  private var restBar: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let remaining = max(0, Int(ceil(restEnd - context.date.timeIntervalSince1970)))
      if remaining > 0 {
        HStack {
          Image(systemName: "timer").foregroundStyle(HybrdStyle.terraText)
          Text("Rest").font(.subheadline)
          Text(clock(Double(remaining))).font(.headline.monospacedDigit())
          Spacer()
          Button("+15s") { restEnd += 15 }.font(.subheadline.weight(.medium))
          Button("Skip") { restEnd = 0 }.font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(HybrdStyle.terraWash)
      }
    }
  }

  private var runForm: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 10) {
          Text(draft.workout.title).font(.title2.weight(.semibold))
          Text("Prescribed: " + draft.workout.summary).font(.subheadline).foregroundStyle(HybrdStyle.muted)
          Text("Enter the run you completed.").font(.subheadline)
        }.padding(.vertical, 8)
      }
      Section("Actual results") {
        LabeledContent("Distance · km") {
          TextField("0.0", value: $draft.distanceKilometers, format: .number.precision(.fractionLength(0...2)))
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            .accessibilityLabel("Actual distance in kilometers")
        }
        LabeledContent("Duration · min") {
          TextField("0", value: $draft.durationMinutes, format: .number)
            .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            .accessibilityLabel("Actual duration in minutes")
        }
        if draft.distanceKilometers > 0 && draft.durationMinutes > 0 {
          LabeledContent("Average pace", value: paceLabel)
        }
      }
      effortSection
      Section {
        Button("Save run") { showFinish = true }.fontWeight(.semibold).disabled(!draft.canFinish)
      } footer: {
        Text("Distance and time aren’t recorded automatically in this build.")
      }
    }
    .scrollContentBackground(.hidden)
  }

  private var paceLabel: String {
    guard draft.distanceKilometers.isFinite, (0.001...500).contains(draft.distanceKilometers), (1...2_880).contains(draft.durationMinutes) else { return "—" }
    let seconds = Int(Double(draft.durationMinutes * 60) / draft.distanceKilometers)
    return "\(seconds / 60):\(String(format: "%02d", seconds % 60)) /km"
  }

  private var effortSection: some View {
    Section("How did it feel?") {
      LabeledContent("Session effort", value: "\(draft.effort) / 10")
      Slider(value: Binding(get: { Double(draft.effort) }, set: { draft.effort = Int($0) }), in: 1...10, step: 1) {
        Text("Session effort")
      } minimumValueLabel: {
        Text("Easy").font(.caption)
      } maximumValueLabel: {
        Text("Max").font(.caption)
      }
      TextField("Session notes", text: $draft.notes, axis: .vertical).lineLimit(3...6)
    }
  }

  private var notesSheet: some View {
    NavigationStack {
      Form { effortSection }
        .navigationTitle("Effort & notes").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSessionNotes = false } } }
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
