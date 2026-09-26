import SwiftUI

struct StrengthBestsView: View {
  @Environment(\.trainingUnits) private var units
  @Bindable var editor: AthleteProfileEditor
  @Environment(TrainingStore.self) private var store
  @State private var editing: StrengthPersonalBest?
  @State private var adding = false
  @State private var showLogged = false
  @State private var loggedCandidates: [StrengthPersonalBest] = []

  var body: some View {
    List {
      Section {
        ProfileSectionHero(eyebrow: L10n.text("Strength PRs"), title: L10n.text("Built one rep at a time."),
          subtitle: L10n.text("Keep the sets you’re proud of. Record the weight and reps together."),
          artwork: .strength, tone: .violet)
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      Section {
        if editor.details.strengthBests.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("Your first milestone")).font(.headline)
            Text(L10n.text("Add a lift and its best set to start your record list."))
              .font(.subheadline).foregroundStyle(HybrdStyle.muted)
          }.padding(.vertical, 8).listRowBackground(SessionPalette.wash(.violet))
        }
        ForEach(editor.details.strengthBests) { record in
          Button { editing = record } label: {
            StrengthRecordCard(record: record)
          }
          .buttonStyle(.plain).listRowBackground(SessionPalette.wash(.violet))
          .accessibilityHint(L10n.text("Edit this personal record"))
        }
        .onDelete { editor.details.strengthBests.remove(atOffsets: $0) }
      } header: { Text(L10n.text("Personal records")) }
      Section {
        Button(L10n.text("Add strength PR"), systemImage: "plus") { adding = true }
          .buttonStyle(HybrdPrimaryButtonStyle())
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
      Section {
        Button {
          loggedCandidates = LoggedStrengthRecords.candidates(from: store.state.results)
          showLogged = true
        } label: {
          Label(L10n.text("Find best sets in my logs"), systemImage: "clock.arrow.circlepath")
            .foregroundStyle(SessionPalette.ink(.violet)).padding(.vertical, 6)
        }
      } footer: {
        Text(L10n.text("A five-rep best stays a five-rep best. Logged candidates need your review; existing PRs are never replaced automatically.")).lineLimit(nil).fixedSize(horizontal: false, vertical: true)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden).background(HybrdStyle.background)
    .navigationTitle(L10n.text("Strength PRs")).navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $adding) { StrengthBestEditorView { save($0) } }
    .sheet(item: $editing) { record in StrengthBestEditorView(record: record) { save($0) } }
    .sheet(isPresented: $showLogged) {
      NavigationStack {
        List {
          if loggedCandidates.isEmpty {
            ContentUnavailableView(L10n.text("No logged sets yet"), systemImage: "dumbbell",
              description: Text(L10n.text("Complete a strength session to find recorded best sets here.")))
          }
          ForEach(loggedCandidates) { record in
            let exists = editor.details.strengthBests.contains {
              $0.exerciseName.localizedCaseInsensitiveCompare(record.exerciseName) == .orderedSame
            }
            Section {
              StrengthRecordCard(record: record, showsEdit: false)
              if exists { Label(L10n.text("Already added"), systemImage: "checkmark").font(.subheadline) }
              else {
                Button(L10n.text("Add this record"), systemImage: "plus") { save(record) }
                  .accessibilityLabel(L10n.text("Add \(record.localizedExerciseName), \(units.weightText(record.kilograms)) × \(record.reps)"))
              }
            }.listRowBackground(SessionPalette.wash(.violet))
          }
        }
        .scrollContentBackground(.hidden).background(HybrdStyle.background)
        .navigationTitle(L10n.text("Logged best sets"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { showLogged = false } } }
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

private struct StrengthRecordCard: View {
  @Environment(\.trainingUnits) private var units
  var record: StrengthPersonalBest
  var showsEdit = true
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(alignment: .leading, spacing: 15) {
      HStack(alignment: .top, spacing: 12) {
        Text(record.localizedExerciseName).font(.headline).foregroundStyle(HybrdStyle.ink)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        if showsEdit {
          Image(systemName: "pencil").font(.subheadline).foregroundStyle(SessionPalette.ink(.violet))
            .accessibilityHidden(true)
        }
      }
      let layout = typeSize.isAccessibilitySize ?
        AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) :
        AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 20))
      layout {
        metric(units.weightNumber(record.kilograms), unit: units.weight.symbol)
        metric(String(record.reps), unit: L10n.text("reps"))
      }
      Text(record.source == .logged ? L10n.text("From your logged sets") : L10n.text("Entered by you"))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
    }
    .padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }

  private func metric(_ value: String, unit: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 5) {
      Text(value).font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
        .foregroundStyle(SessionPalette.ink(.violet))
      Text(unit).font(.subheadline).foregroundStyle(HybrdStyle.muted)
    }
  }
}
