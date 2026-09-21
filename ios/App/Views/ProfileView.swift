import SwiftUI

struct ProfileView: View {
  @Environment(TrainingStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var profile = TrainingProfile()
  @State private var reviewing = false
  private let weekdays = [(2, "Monday"), (3, "Tuesday"), (4, "Wednesday"), (5, "Thursday"), (6, "Friday"), (7, "Saturday"), (1, "Sunday")]

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Text("Two goals. One you.").font(.title2.bold())
            Text("Start with your goals and a week you can actually follow.")
              .font(.subheadline).foregroundStyle(.secondary)
          }.padding(.vertical, 8)
          TextField("Your name", text: $profile.name).textContentType(.givenName)
        }
        Section("Your direction") {
          Picker("Running", selection: $profile.runningGoal) {
            ForEach(RunningGoal.allCases) { Text($0.rawValue).tag($0) }
          }
          Picker("Strength", selection: $profile.strengthGoal) {
            ForEach(StrengthGoal.allCases) { Text($0.rawValue).tag($0) }
          }
          Picker("Priority", selection: $profile.priority) {
            ForEach(TrainingPriority.allCases) { Text($0.rawValue).tag($0) }
          }
        }
        Section {
          Stepper(value: $profile.weeklyKilometers, in: 3...150, step: 1) {
            LabeledContent("Weekly running", value: "\(Int(profile.weeklyKilometers)) km")
          }
          Stepper(value: $profile.strengthDays, in: 1...4) {
            LabeledContent("Strength sessions", value: "\(profile.strengthDays) / week")
          }
          Picker("Time per session", selection: $profile.sessionMinutes) {
            ForEach([30, 45, 60, 75, 90], id: \.self) { Text("\($0) minutes").tag($0) }
          }
        } header: {
          Text("Your current baseline")
        } footer: {
          Text("Use a recent, comfortable running volume. The starter block begins with easy running and adjustable strength loads.")
        }
        Section {
          ForEach(weekdays, id: \.0) { day, name in
            Toggle(name, isOn: Binding(
              get: { profile.availableDays.contains(day) },
              set: { enabled in
                if enabled { profile.availableDays.insert(day) }
                else { profile.availableDays.remove(day) }
              }))
          }
        } header: {
          Text("Days you can train")
        } footer: {
          Text("Choose at least two days. When time is limited, one day is reserved for running and the remaining strength sessions fit into available days.")
        }
        Section {
          Button("Review starter block") { reviewing = true }
            .font(.headline)
            .disabled(profile.availableDays.count < 2)
        }
        Section {
          LabeledContent("Training data", value: "On this iPhone")
          LabeledContent("Cloud AI", value: "Not connected")
          VStack(alignment: .leading, spacing: 6) {
            Label("Apple Watch", systemImage: "applewatch")
            Text(store.companion.connectionMessage).font(.caption).foregroundStyle(.secondary)
          }
          Button("Send plan to Watch", systemImage: "arrow.triangle.2.circlepath") { store.shareWithWatch() }
        } header: {
          Text("Connections")
        } footer: {
          Text("Cloud sync, HealthKit import, and cloud coaching aren’t enabled in this build. The Watch companion displays your upcoming prescriptions.")
        }
      }
      .navigationTitle("Athlete profile")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
      }
      .onAppear { profile = store.profile }
      .sheet(isPresented: $reviewing) {
        StarterReviewView(profile: profile) {
          if store.accept(profile: profile) { dismiss() }
        }
      }
    }
  }
}

private struct StarterReviewView: View {
  @Environment(\.dismiss) private var dismiss
  var profile: TrainingProfile
  var accept: () -> Void
  private var proposal: TrainingPlan { TrainingEngine.makePlan(profile: profile) }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Text("Your starting point").font(.title2.bold())
          Text("Four weeks of easy running and foundational strength. Review the first week before accepting.")
            .foregroundStyle(.secondary)
          LabeledContent("Running goal", value: profile.runningGoal.rawValue)
          LabeledContent("Strength goal", value: profile.strengthGoal.rawValue)
        }
        Section("First seven days") {
          ForEach(proposal.workouts.filter { $0.date < TrainingEngine.date(Calendar.current.startOfDay(for: Date()), offset: 7) }) { workout in
            VStack(alignment: .leading, spacing: 6) {
              Text(workout.date.formatted(.dateTime.weekday(.wide))).font(.caption).foregroundStyle(.secondary)
              SessionRow(workout: workout, status: workout.effort)
            }
          }
        }
        Section {
          Text("Running volume stays steady for three weeks, then eases in week four. Session time limits may reduce your requested distance. This is a starter block, not a race-specific plan.")
            .font(.subheadline).foregroundStyle(.secondary)
          Text("Accepting replaces unstarted future sessions. Completed and in-progress sessions and previous plan versions are preserved.")
            .font(.subheadline).foregroundStyle(.secondary)
          Button("Accept starter block") { accept(); dismiss() }
            .font(.headline)
        }
      }
      .navigationTitle("Review your plan")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
    }
  }
}
