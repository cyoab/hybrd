import SwiftUI

struct StrengthBestsView: View {
  @Bindable var editor: AthleteProfileEditor
  @Environment(TrainingStore.self) private var store
  @State private var editing: StrengthPersonalBest?
  @State private var adding = false
  @State private var showLogged = false

  var body: some View {
    List {
      Section {
        Label("Your strongest sets.", systemImage: "trophy").font(.headline).foregroundStyle(SessionPalette.ink(.violet))
        Text("Record a weight and rep count together. A five-rep best stays a five-rep best; we don’t turn it into an estimated max.")
          .font(.subheadline).foregroundStyle(.secondary)
      }
      Section("Personal records") {
        ForEach(editor.details.strengthBests) { record in
          Button { editing = record } label: {
            VStack(alignment: .leading, spacing: 6) {
              Text(record.exerciseName).font(.headline).foregroundStyle(HybrdStyle.ink)
              Text(record.summary).font(.subheadline.monospacedDigit()).foregroundStyle(SessionPalette.ink(.violet))
              Text(record.source == .logged ? "From your logged sets" : "Entered by you").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 5)
          }.buttonStyle(.plain)
        }
        .onDelete { editor.details.strengthBests.remove(atOffsets: $0) }
        Button("Add strength PR", systemImage: "plus") { adding = true }
      }
      Section {
        Button("Find best sets in my logs", systemImage: "clock.arrow.circlepath") { showLogged = true }
      } footer: { Text("Logged candidates are reviewed before adding. Existing PRs are never replaced automatically.") }
    }
    .navigationTitle("Strength PRs").navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $adding) { StrengthBestEditorView { save($0) } }
    .sheet(item: $editing) { record in StrengthBestEditorView(record: record) { save($0) } }
    .sheet(isPresented: $showLogged) {
      NavigationStack {
        List {
          let candidates = LoggedStrengthRecords.candidates(from: store.state.results)
          if candidates.isEmpty {
            ContentUnavailableView("No logged sets yet", systemImage: "dumbbell",
              description: Text("Complete a strength session to find recorded best sets here."))
          }
          ForEach(candidates) { record in
            let exists = editor.details.strengthBests.contains { $0.exerciseName.localizedCaseInsensitiveCompare(record.exerciseName) == .orderedSame }
            HStack {
              VStack(alignment: .leading, spacing: 5) {
                Text(record.exerciseName).font(.headline)
                Text(record.summary).foregroundStyle(.secondary)
              }
              Spacer()
              if exists { Text("Already added").font(.caption).foregroundStyle(.secondary) }
              else { Button("Add") { save(record) }.buttonStyle(.bordered) }
            }.padding(.vertical, 4)
          }
        }
        .navigationTitle("Logged best sets")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showLogged = false } } }
      }
    }
  }
  private func save(_ record: StrengthPersonalBest) {
    editor.details.strengthBests.removeAll {
      $0.id == record.id || $0.exerciseID == record.exerciseID ||
        $0.exerciseName.localizedCaseInsensitiveCompare(record.exerciseName) == .orderedSame
    }
    editor.details.strengthBests.append(record)
    editor.details.strengthBests.sort { $0.exerciseName < $1.exerciseName }
  }
}
