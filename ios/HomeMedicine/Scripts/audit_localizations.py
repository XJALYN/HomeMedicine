#!/usr/bin/env python3
"""Audit Localizable.strings coverage against English source and Swift usage."""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "HomeMedicine", "Resources", "Localizations")
SRC = os.path.join(ROOT, "HomeMedicine")

DYNAMIC_KEYS = [
    "scan.step.front", "scan.step.back", "scan.step.left", "scan.step.right", "scan.step.top", "scan.step.bottom",
    "usage_record.intake", "usage_record.stock_in", "usage_record.depleted", "usage_record.disposed",
    "paywall.current_plan.free", "paywall.current_plan.pro", "paywall.current_plan.family",
    "paywall.trigger.general", "paywall.trigger.medicineLimit", "paywall.trigger.aiScanLimit",
    "paywall.trigger.reminderLimit", "paywall.trigger.memberLimit", "paywall.trigger.export",
    "paywall.trigger.familySharing",
    "unit.pill", "unit.tablet", "unit.bag", "unit.bottle", "unit.stick", "unit.box",
    "instruction.before", "instruction.after", "instruction.with",
    "relation.self", "relation.father", "relation.mother", "relation.child", "relation.other",
    "sharing.error.container_unavailable", "sharing.error.icloud_unavailable",
    "sharing.error.cloudkit_not_configured", "sharing.error.record_not_synced",
    "sharing.error.share_creation_failed",
]


def read_strings(path: str) -> dict:
    mapping = {}
    if not os.path.exists(path):
        return mapping
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line.startswith('"'):
                continue
            parts = line.split('"')
            if len(parts) >= 4:
                mapping[parts[1]] = parts[3]
    return mapping


def extract_swift_keys() -> set:
    keys = set(DYNAMIC_KEYS)
    pattern = re.compile(r'L10n\.t\("([^"]+)"')
    for dirpath, _, filenames in os.walk(SRC):
        for name in filenames:
            if not name.endswith(".swift"):
                continue
            with open(os.path.join(dirpath, name), encoding="utf-8") as f:
                keys.update(pattern.findall(f.read()))
    return keys


def main():
    parser = argparse.ArgumentParser(description="Audit localization files")
    parser.add_argument("--strict", action="store_true", help="Exit 1 if any non-en locale matches English")
    args = parser.parse_args()

    en_path = os.path.join(RES, "en.lproj", "Localizable.strings")
    en = read_strings(en_path)
    swift_keys = extract_swift_keys()
    missing_in_en = sorted(swift_keys - set(en))
    if missing_in_en:
        print("Keys used in Swift but missing from en.lproj:")
        for key in missing_in_en:
            print(f"  - {key}")
        if args.strict:
            sys.exit(1)

    langs = sorted(
        name.replace(".lproj", "")
        for name in os.listdir(RES)
        if name.endswith(".lproj")
    )

    exit_code = 0
    for lang in langs:
        if lang == "en":
            continue
        loc = read_strings(os.path.join(RES, f"{lang}.lproj", "Localizable.strings"))
        untranslated = [k for k, v in loc.items() if k in en and v == en[k]]
        used_untranslated = [k for k in untranslated if k in swift_keys]
        print(f"\n{lang}: {len(untranslated)} identical to English ({len(used_untranslated)} used in Swift)")
        if used_untranslated and args.strict:
            exit_code = 1
            for key in used_untranslated[:20]:
                print(f"  - {key}")
            if len(used_untranslated) > 20:
                print(f"  ... and {len(used_untranslated) - 20} more")

    if args.strict and exit_code:
        sys.exit(1)
    print("\nAudit complete.")


if __name__ == "__main__":
    main()
