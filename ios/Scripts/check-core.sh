#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
localization_bundle=$(mktemp -d /tmp/hybrd-localization.XXXXXX)
trap 'rm -rf "$localization_bundle"' EXIT
xcrun xcstringstool compile Shared/Resources/Localizable.xcstrings --output-directory "$localization_bundle"
export HYBRD_LOCALIZATION_BUNDLE="$localization_bundle"
python3 Scripts/check-localization.py
python3 Scripts/generate-onboarding-wire.py --check
swiftc -DDEBUG -module-cache-path /tmp/hybrd-swift-module-cache \
  Shared/L10n.swift \
  Shared/AthleteDetails.swift \
  Shared/GymEquipment.swift \
  Shared/HeartRatePlanUpgrade.swift \
  Shared/HeartRateZone.swift \
  Shared/MuscleGroup.swift \
  Shared/PersonalHeartRateZones.swift \
  Shared/ProgressPeriod.swift \
  Shared/ProgressMilestone.swift \
  Shared/ProgressComparison.swift \
  Shared/ProgressSnapshot.swift \
  Shared/RunGPSFilter.swift \
  Shared/RunPaceReading.swift \
  Shared/RunLiveMetrics.swift \
  Shared/RunGuidance.swift \
  Shared/RunRecording.swift \
  Shared/StrengthRestTimer.swift \
  Shared/RunTimeline.swift \
  Shared/RunWorkoutType.swift \
  Shared/RunWorkoutTemplate.swift \
  Shared/RunningPersonalBest.swift \
  Shared/SampleTraining.swift \
  Shared/SessionBreakdown.swift \
  Shared/StrengthPersonalBest.swift \
  Shared/StrengthStarterSelection.swift \
  Shared/TrainingEngine.swift \
  Shared/TrainingPlan.swift \
  Shared/TrainingProfile.swift \
  Shared/TrainingUnits.swift \
  Shared/TrainingWeightUnit.swift \
  Shared/TrainingDistanceUnit.swift \
  Shared/CompanionSnapshot.swift \
  Shared/TrainingWeekWindow.swift \
  Shared/TrainingWorkout.swift \
  Shared/WeeklyTrainingSummary.swift \
  Shared/WorkoutResult.swift \
  App/Models/Onboarding/*.swift \
  App/Models/Backend/*.swift \
  App/Models/Backend/Generated/*.swift \
  App/Models/AthleteProfileEditor.swift \
  App/Models/TrainingState.swift \
  App/Models/LocalCoach.swift \
  App/Models/ExerciseCatalog.swift \
  Tests/*.swift -o /tmp/hybrd-core-checks
/tmp/hybrd-core-checks
