import SwiftUI

struct WorkoutLoggerView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State var draft: WorkoutDraft
  @State private var finished = false
  @State private var showFinish = false
  @AppStorage("hybrd.restEnd") private var restEnd = 0.0

  private var completedSets: Int { draft.sets.filter(\.isComplete).count }
  private var canFinish: Bool {
    if draft.workout.kind == .run {
      return draft.distanceKilometers > 0 && draft.distanceKilometers <= 500 && draft.durationMinutes > 0 && draft.durationMinutes <= 2_880
    }
    return completedSets > 0 && draft.sets.filter(\.isComplete).allSatisfy { $0.reps > 0 && $0.reps <= 100 && $0.kilograms >= 0 && $0.kilograms <= 1_000 }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(alignment: .leading, spacing: 6) {
            Text(draft.workout.title).font(.title2.bold())
            Text("Prescribed: \(draft.workout.summary)").font(.subheadline).foregroundStyle(.secondary)
            Label("Saved on this iPhone as you log", systemImage: "internaldrive")
              .font(.caption).foregroundStyle(.secondary)
          }.padding(.vertical, 6)
        }
        if draft.workout.kind == .run {
          Section {
            HStack {
              Text("Distance")
              Spacer()
              TextField("0.0", value: $draft.distanceKilometers, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .accessibilityLabel("Actual distance in kilometers")
              Text("km").foregroundStyle(.secondary)
            }
            HStack {
              Text("Duration")
              Spacer()
              TextField("0", value: $draft.durationMinutes, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                .accessibilityLabel("Actual duration in minutes")
              Text("min").foregroundStyle(.secondary)
            }
          } header: {
            Text("What you completed")
          } footer: {
            Text("Enter your actual run. Distance and time aren’t recorded automatically.")
          }
        } else {
          ForEach(draft.workout.exercises) { exercise in
            Section {
              ForEach(draft.sets.indices.filter { draft.sets[$0].exerciseName == exercise.name }, id: \.self) { index in
                setRow(index: index)
              }
            } header: {
              Text(exercise.name)
            } footer: {
              Text(exercise.note)
            }
          }
          Section("Rest timer") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
              let remaining = max(0, Int(ceil(restEnd - context.date.timeIntervalSince1970)))
              HStack {
                Label(remaining > 0 ? "\(remaining / 60):\(String(format: "%02d", remaining % 60))" : "Ready for your next set", systemImage: "timer")
                  .monospacedDigit()
                Spacer()
                Button(remaining > 0 ? "Reset 90s" : "Start 90s") {
                  restEnd = Date().addingTimeInterval(90).timeIntervalSince1970
                }.buttonStyle(.borderless)
              }
            }
          }
        }
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
        Section {
          Button {
            showFinish = true
          } label: {
            Text("Finish session").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
          }
          .disabled(!canFinish)
        } footer: {
          if draft.workout.kind == .strength {
            Text("\(completedSets) of \(draft.sets.count) sets checked. Unchecked sets won’t be recorded. A partly completed session still counts.")
          }
        }
      }
      .navigationTitle("Log session")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Save for later") { store.saveDraft(draft); dismiss() }
        }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        }
      }
      .task { store.saveDraft(draft) }
      .onChange(of: draft) { _, newValue in if !finished { store.saveDraft(newValue) } }
      .sensoryFeedback(.success, trigger: completedSets)
      .confirmationDialog("Save this session?", isPresented: $showFinish, titleVisibility: .visible) {
        Button("Save completed work") {
          if store.finish(draft) {
            finished = true
            restEnd = 0
            dismiss()
          }
        }
      } message: {
        Text("Your actual results will be saved separately from the original prescription.")
      }
    }
  }

  private func setRow(index: Int) -> some View {
    HStack(spacing: 12) {
      let position = (draft.sets[..<index].filter { $0.exerciseName == draft.sets[index].exerciseName }.count) + 1
      Text("\(position)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 20)
      VStack(alignment: .leading, spacing: 3) {
        Text("KG").font(.caption2).foregroundStyle(.secondary)
        TextField("0", value: $draft.sets[index].kilograms, format: .number.precision(.fractionLength(0...1)))
          .keyboardType(.decimalPad)
          .accessibilityLabel("\(draft.sets[index].exerciseName), set \(position), kilograms")
      }
      VStack(alignment: .leading, spacing: 3) {
        Text("REPS").font(.caption2).foregroundStyle(.secondary)
        TextField("Reps", value: $draft.sets[index].reps, format: .number)
          .keyboardType(.numberPad)
          .accessibilityLabel("\(draft.sets[index].exerciseName), set \(position), reps")
      }
      Toggle(isOn: $draft.sets[index].isComplete) {
        Label("Set \(position) completed", systemImage: draft.sets[index].isComplete ? "checkmark.square.fill" : "square")
          .labelStyle(.iconOnly)
      }
      .toggleStyle(.button).buttonStyle(.borderless)
      .font(.title2)
      .onChange(of: draft.sets[index].isComplete) { _, completed in
        if completed { restEnd = Date().addingTimeInterval(90).timeIntervalSince1970 }
      }
    }
    .padding(.vertical, 4)
  }
}
