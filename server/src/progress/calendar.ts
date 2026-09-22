// Arithmetic on civil dates, never elapsed 86,400-second periods in a time zone.
export function addDays(day: string, count: number): string {
  const date = new Date(`${day}T12:00:00.000Z`);
  date.setUTCDate(date.getUTCDate() + count);
  return date.toISOString().slice(0, 10);
}
export function calendar(timezone: string) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    calendar: "iso8601",
    numberingSystem: "latn",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const day = (instant: Date) => {
    const parts = Object.fromEntries(
      formatter.formatToParts(instant).map((p) => [p.type, p.value]),
    );
    return `${parts.year?.padStart(4, "0")}-${parts.month}-${parts.day}`;
  };
  return {
    day,
    nextMidnight(now: Date) {
      const today = day(now);
      let low = now.getTime(),
        high = low + 48 * 3600_000;
      // Also handles 23/25-hour days, midnight transitions and skipped civil days.
      while (high - low > 1) {
        const middle = Math.floor((low + high) / 2);
        if (day(new Date(middle)) === today) low = middle;
        else high = middle;
      }
      return new Date(high);
    },
  };
}
