import SwiftUI

struct PlanView: View {
  @Environment(TrainingStore.self) private var store
  @State private var offset = 0
  private var week: Date { TrainingEngine.date(TrainingEngine.startOfWeek(containing: Date()), offset: offset * 7) }
  private var sessions: [TrainingWorkout] { store.sessions(in: week) }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            Button("Previous week", systemImage: "chevron.left") { offset -= 1 }
              .labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
            Spacer()
            VStack(spacing: 4) {
              Text(week.formatted(.dateTime.month(.abbreviated).day()) + " – " + TrainingEngine.date(week, offset: 6).formatted(.dateTime.month(.abbreviated).day()))
                .font(.headline)
              Text(offset == 0 ? "This week" : "Training calendar").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Next week", systemImage: "chevron.right") { offset += 1 }
              .labelStyle(.iconOnly).buttonStyle(.borderless).frame(minWidth: 44, minHeight: 44)
          }
          HStack {
            Label(String(format: "%.1f km", Double(sessions.reduce(0) { $0 + $1.distanceMeters }) / 1_000), systemImage: "figure.run")
            Spacer()
            Label("\(sessions.filter { $0.kind == .strength }.count) strength", systemImage: "dumbbell.fill")
          }.font(.subheadline).foregroundStyle(.secondary)
        } footer: {
          Text(store.profile.isSample ? "Sample starter block · set your goals from Today to personalize it." : "Your accepted starter block. Open a session to log it or review a schedule change.")
        }

        ForEach(0..<7) { day in
          let date = TrainingEngine.date(week, offset: day)
          let workouts = sessions.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
          Section {
            if workouts.isEmpty {
              Label("Recovery / no session", systemImage: "leaf")
                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
              ForEach(workouts) { workout in
                NavigationLink {
                  WorkoutDetailView(workout: workout)
                } label: {
                  SessionRow(workout: workout, status: store.status(of: workout))
                }
              }
            }
          } header: {
            Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + (Calendar.current.isDateInToday(date) ? " · Today" : ""))
          }
        }
        Section {
          NavigationLink {
            PlanHistoryView()
          } label: {
            Label("Plan history", systemImage: "clock.arrow.circlepath")
          }
        }
      }
      .navigationTitle("Your plan")
      .toolbar {
        if offset != 0 {
          ToolbarItem(placement: .topBarTrailing) {
            Button("Today") { offset = 0 }
          }
        }
      }
    }
  }
}

private struct PlanHistoryView: View {
  @Environment(TrainingStore.self) private var store
  var body: some View {
    List(Array(store.state.plans.enumerated()).reversed(), id: \.element.id) { index, plan in
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Version \(index + 1)").font(.headline)
          Spacer()
          if plan.id == store.plan.id { Text("Active").font(.caption.bold()).foregroundStyle(.tint) }
        }
        Text(plan.reason).font(.subheadline)
        Text(plan.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
      }.padding(.vertical, 6)
    }
    .navigationTitle("Plan history")
  }
}
