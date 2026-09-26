import type { z } from "zod";
import type { Citation } from "./schemas";

// Reviewed source identities and bounded summaries, not a prescription policy.
// A citation's existence does not establish that generated prose entails its claim.
export const evidence: z.infer<typeof Citation>[] = [
  {
    id: "acsm-resistance-2026",
    version: 1,
    title: "ACSM: Resistance Training Prescription for Healthy Adults (2026)",
    url: "https://pubmed.ncbi.nlm.nih.gov/41843416/",
    claim:
      "Resistance-training outcomes depend on the goal and prescription; strength, hypertrophy and power require distinct considerations.",
    limitations:
      "Overview of reviews in healthy adults. Studied high loads or volumes are not universal novice starting prescriptions or rehabilitation guidance.",
  },
  {
    id: "concurrent-training-2022",
    version: 1,
    title: "Compatibility of Concurrent Aerobic and Strength Training (2022)",
    url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC8891239/",
    claim:
      "The aggregate evidence distinguishes maximal strength and hypertrophy from explosive-strength interference, with session scheduling relevant to the latter.",
    limitations:
      "Population averages cannot determine an individual's response or a universal required separation interval.",
  },
  {
    id: "endurance-distribution-2025",
    version: 1,
    title:
      "Endurance Training Intensity Distribution: Systematic Review and Meta-analysis (2025)",
    url: "https://pubmed.ncbi.nlm.nih.gov/39888556/",
    claim:
      "The reported overall comparisons did not establish a polarized-versus-pyramidal advantage for main outcomes; training level may matter.",
    limitations:
      "Study three-zone definitions must not be equated with an athlete's five heart-rate zones. This does not establish a universal 80/20 prescription.",
  },
  {
    id: "running-load-cohort-2025",
    version: 1,
    title: "Running-session distance and overuse injury cohort (2025)",
    url: "https://pubmed.ncbi.nlm.nih.gov/40623829/",
    claim:
      "Spikes in an individual run's distance relative to recent longest runs were associated with overuse injury.",
    limitations:
      "Observational association, not causality or an individual injury predictor; it does not validate a weekly 10% safety guarantee.",
  },
];
