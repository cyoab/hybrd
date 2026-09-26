#!/usr/bin/env python3
"""Audit translation coverage and argument safety; optionally check compiler-extracted keys."""
import argparse
import collections
import itertools
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {"en", "es", "pt-BR", "fr"}
FORMAT = re.compile(r"%(?:(\d+)\$)?(?:\.\d+)?(lld|ld|lf|d|f|@)")

def arguments(value):
    result = collections.Counter()
    for index, match in enumerate(FORMAT.finditer(value), 1):
        result[(int(match[1]) if match[1] else index, match[2])] += 1
    return result

def resolved_values(entry):
    if "variations" in entry:
        return [value for variant in entry["variations"]["plural"].values() for value in resolved_values(variant)]
    text = entry["stringUnit"]["value"]
    assert entry["stringUnit"]["state"] == "translated" and text.strip()
    versions = [text]
    for name, substitution in entry.get("substitutions", {}).items():
        variants = resolved_values(substitution)
        variants = [value.replace("%" + substitution["formatSpecifier"], "%" + str(substitution["argNum"]) + "$" + substitution["formatSpecifier"]) for value in variants]
        versions = [value.replace("%#@" + name + "@", replacement) for value, replacement in itertools.product(versions, variants)]
    return versions

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--stringsdata-root", type=Path, help="Bitrig build's Intermediates.noindex/hybrd.build directory")
    args = parser.parse_args()
    catalog = None
    for path in [ROOT / "Shared/Resources/Localizable.xcstrings", ROOT / "App/Resources/InfoPlist.xcstrings", ROOT / "Watch/Resources/InfoPlist.xcstrings"]:
        data = json.loads(path.read_text())
        assert data["sourceLanguage"] == "en"
        for key, entry in data["strings"].items():
            assert set(entry["localizations"]) == LANGUAGES, (path, key, "Missing language")
            for language, translation in entry["localizations"].items():
                for value in resolved_values(translation):
                    assert arguments(value) == arguments(key), (path, key, language, value, "Changed format arguments")
                    assert "%#@" not in value
        if path.name == "Localizable.xcstrings":
            catalog = data["strings"]
    if args.stringsdata_root:
        missing = set()
        for path in args.stringsdata_root.rglob("*.stringsdata"):
            for value in json.loads(path.read_text()).get("tables", {}).get("Localizable", []):
                if value["key"].strip() and value["key"] not in catalog:
                    missing.add(value["key"])
        assert not missing, "Untranslated compiler-extracted keys: " + repr(sorted(missing))
    project = json.loads((ROOT / "Project.json").read_text())
    for target in project["targets"].values():
        assert set(target["info"]["properties"]["CFBundleLocalizations"]) == LANGUAGES
        assert {"path": "Shared"} in target["sources"]
    print(f"PASS: {len(catalog)} strings in four languages, permission catalogs, plural variants, format argument safety and both target resources")

if __name__ == "__main__":
    main()
