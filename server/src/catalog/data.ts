// Stable, versioned reference IDs; never change an existing ID's meaning.
export const catalogVersion = 2;
export const catalogId = (group: number, index: number) =>
  `10000000-0000-4000-8${String(group).padStart(3, "0")}-${String(index).padStart(12, "0")}`;
export const equipmentNames = [
  "Barbell",
  "Dumbbells",
  "Bench",
  "Rack",
  "Pull-up bar",
  "Cable machine",
  "Leg press",
  "Kettlebell",
  "Resistance band",
  "Bodyweight",
  "EZ curl bar",
  "Weight plates",
  "Leg extension",
  "Leg curl",
  "Chest press",
  "Lat pulldown",
  "Seated row",
  "Smith machine",
  "Medicine ball",
  "Stability ball",
  "Foam roller",
];
export const muscleNames = [
  "Quadriceps",
  "Hamstrings",
  "Glutes",
  "Calves",
  "Chest",
  "Back",
  "Shoulders",
  "Biceps",
  "Triceps",
  "Core",
];
// name, movement pattern, primary muscle indices, secondary indices, equipment indices, unilateral
export const exerciseData: [
  string,
  string,
  number[],
  number[],
  number[],
  boolean,
][] = [
  ["Back squat", "squat", [0, 2], [1, 9], [0, 3], false],
  ["Front squat", "squat", [0], [2, 9], [0, 3], false],
  ["Goblet squat", "squat", [0, 2], [9], [1], false],
  ["Romanian deadlift", "hinge", [1, 2], [5, 9], [0], false],
  ["Deadlift", "hinge", [1, 2], [0, 5, 9], [0], false],
  ["Dumbbell split squat", "lunge", [0, 2], [1], [1], true],
  ["Reverse lunge", "lunge", [0, 2], [1], [1], true],
  ["Step-up", "lunge", [0, 2], [1], [1, 2], true],
  ["Hip thrust", "hinge", [2], [1], [0, 2], false],
  ["Leg press", "squat", [0, 2], [], [6], false],
  ["Standing calf raise", "calf_raise", [3], [], [1], false],
  ["Bench press", "horizontal_push", [4], [6, 8], [0, 2, 3], false],
  ["Dumbbell bench press", "horizontal_push", [4], [6, 8], [1, 2], false],
  ["Push-up", "horizontal_push", [4], [6, 8, 9], [9], false],
  ["Overhead press", "vertical_push", [6], [8], [0], false],
  ["Dumbbell shoulder press", "vertical_push", [6], [8], [1], false],
  ["Bent-over row", "horizontal_pull", [5], [7], [0], false],
  ["Single-arm dumbbell row", "horizontal_pull", [5], [7], [1, 2], true],
  ["Cable row", "horizontal_pull", [5], [7], [5], false],
  ["Pull-up", "vertical_pull", [5], [7], [4], false],
  ["Lat pulldown", "vertical_pull", [5], [7], [5], false],
  ["Dumbbell curl", "elbow_flexion", [7], [], [1], false],
  ["Triceps pushdown", "elbow_extension", [8], [], [5], false],
  ["Lateral raise", "shoulder_abduction", [6], [], [1], false],
  ["Plank", "core", [9], [], [9], false],
  ["Side plank", "core", [9], [], [9], true],
  ["Dead bug", "core", [9], [], [9], false],
  ["Kettlebell swing", "hinge", [2, 1], [9], [7], false],
];
export const slug = (name: string) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-$/g, "");
