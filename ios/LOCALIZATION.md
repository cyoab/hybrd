# Localization

hybrd supports English (`en`), Spanish (`es`, with Latin American wording), Brazilian Portuguese (`pt-BR`), and French (`fr`). Both the iPhone and Watch targets ship the same `Shared/Resources/Localizable.xcstrings`. Each target has its own `InfoPlist.xcstrings` for Health and location permission prompts.

The OS selects the app language from the user's preferred languages, including the iOS per-app language setting. Regional Spanish and French preferences resolve to the shared Spanish/French resources. Unsupported languages fall back to English. Changing an iPhone's app language does not rewrite the Watch's language preferences; Watch renders shared prescriptions in its own selected language.

## Display and storage

- `L10n.text` uses native Foundation string localization, including typed interpolation and catalog plural rules. Swift's compiler extracts keys from these calls and from native SwiftUI literals.
- `L10n.content` localizes known built-in English content keys at display time. Exercise/workout names, cues, enum raw values, IDs, kilograms, meters, timestamps, and Watch transfer payloads retain their canonical values.
- Built-in run recipes, starter strength exercises, common PR exercise choices, muscle and equipment selections are translated. Search for a common PR exercise accepts its translated name or its original source name. The larger public exercise database retains its original source names for entries without a curated translation; user-written names and notes also remain as entered.
- New plan changes include optional typed metadata so their explanation can be rendered in any supported language. Old free-form history explanations and old coach conversations remain in the language in which they were recorded. Legacy plans without metadata continue to decode.
- Dates, weekdays, decimal input, numbers, and percentages use the user's regional settings. Weight and distance preferences remain independent of language and region.
- The local rule-based coach recognizes the shipped question prompts in all four languages. It remains a local explanatory feature; this change does not connect a cloud AI or Strava backend.

## Adding or changing text

Use a complete `L10n.text("…")` sentence for computed strings, including all interpolated arguments. Keep full accessibility labels even when a visual column needs an abbreviated translation. Do not translate enum raw values, asset/SF Symbol names, exercise IDs, JSON fields, matching keys, or saved measurements.

Add all four languages in the catalog, with plural variants for counts. Prefer native substitutions when a sentence has independently variable quantities (for example, sets and repetitions). Keep source English keys for existing built-in prescriptions stable. When adding public-catalog translations, use explicit, reviewed names and preserve the source exercise IDs and aliases.

## Verification

Run `bash ios/Scripts/check-core.sh` from the repository root. It compiles the catalog with Apple's `xcstringstool`, verifies language coverage and interpolation safety, and runs model checks including localized lookups, singular/plural forms, independent set/rep inflection, region fallback, decimal entry, multilingual coach prompts, and legacy decoding.

After a Bitrig build, also run:

```sh
python3 ios/Scripts/check-localization.py --stringsdata-root /path/to/Intermediates.noindex/hybrd.build
```

This compares the actual Swift compiler's extracted strings with the catalog, catching untranslated new UI text. The normal Bitrig build validates both simulator targets and packages the localized resources.

Local visual review uses the actual SwiftUI workout views in a temporary macOS rendering harness for compact, light/dark, large-text and Watch-sized layouts. This is a layout check, not native iPhone/Watch interaction or VoiceOver validation. Bitrig's iPhone simulator state inspection is currently unavailable; device-language switching and permission prompts should also be reviewed on devices before release.
