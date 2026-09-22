#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swiftc -module-cache-path /tmp/hybrd-swift-module-cache \
  Shared/AthleteDetails.swift \
  Shared/GymEquipment.swift \
  Shared/HeartRatePlanUpgrade.swift \
  Shared/HeartRateZone.swift \
  Shared/MuscleGroup.swift \
  Shared/PersonalHeartRateZones.swift \
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
  Shared/TrainingWeekWindow.swift \
  Shared/TrainingWorkout.swift \
  Shared/WeeklyTrainingSummary.swift \
  Shared/WorkoutResult.swift \
  App/Models/AthleteProfileEditor.swift \
  App/Models/ExerciseCatalog.swift \
  Tests/*.swift -o /tmp/hybrd-core-checks
/tmp/hybrd-core-checks
