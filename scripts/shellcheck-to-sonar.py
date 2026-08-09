#!/usr/bin/env python3
"""Convert shellcheck's json1 output into SonarQube's generic issue format.

SonarQube has no Bash analyzer, so shell scripts are invisible to it. Importing
shellcheck's findings as *external issues* is what makes the dashboard reflect
this repo: the imported issues create the file components and attach to them.

Usage:
    shellcheck-to-sonar.py <shellcheck-json1> <sonar-report-out>

Issues are reported at line granularity on purpose. Sonar validates text ranges
against indexed file content, and these files have no language, so column-level
ranges risk being rejected.
"""
import json
import sys

# shellcheck level -> (software quality, Sonar severity, clean code attribute)
LEVEL_MAP = {
    "error":   ("RELIABILITY",    "HIGH",   "LOGICAL"),
    "warning": ("RELIABILITY",    "MEDIUM", "LOGICAL"),
    "info":    ("MAINTAINABILITY", "LOW",   "CLEAR"),
    "style":   ("MAINTAINABILITY", "LOW",   "CONVENTIONAL"),
}
DEFAULT = ("MAINTAINABILITY", "LOW", "CLEAR")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    with open(sys.argv[1], encoding="utf-8") as fh:
        comments = json.load(fh).get("comments", [])

    rules, issues = {}, []
    for c in comments:
        code = f"SC{c['code']}"
        rule_id = f"shellcheck:{code}"
        quality, severity, attribute = LEVEL_MAP.get(c.get("level", ""), DEFAULT)

        rules.setdefault(rule_id, {
            "id": rule_id,
            "name": f"shellcheck {code}",
            "description": f"See https://www.shellcheck.net/wiki/{code}",
            "engineId": "shellcheck",
            "cleanCodeAttribute": attribute,
            "impacts": [{"softwareQuality": quality, "severity": severity}],
        })

        line = max(1, int(c.get("line", 1)))
        issues.append({
            "ruleId": rule_id,
            "primaryLocation": {
                "message": c.get("message", code),
                "filePath": c["file"].lstrip("./"),
                "textRange": {"startLine": line, "endLine": line},
            },
        })

    with open(sys.argv[2], "w", encoding="utf-8") as fh:
        json.dump({"rules": list(rules.values()), "issues": issues}, fh, indent=2)

    print(f"{len(issues)} shellcheck finding(s) across {len(rules)} rule(s) "
          f"-> {sys.argv[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
