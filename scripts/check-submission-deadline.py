"""Check the 2026-2027 forecast cutoff using GitHub's pull request event time."""

import json
import re
import sys
from datetime import date, datetime, time, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo


FIRST_ROUND = date(2026, 10, 24)
LAST_ROUND = date(2027, 5, 29)
TORONTO = ZoneInfo("America/Toronto")
FILE_NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})-.+\.csv$")


def check(event_path: Path, changed_files_path: Path) -> None:
    event = json.loads(event_path.read_text(encoding="utf-8"))
    pull_request = event["pull_request"]
    timestamp = (
        pull_request["created_at"]
        if event["action"] == "opened"
        else pull_request["updated_at"]
    )
    submitted_at = datetime.fromisoformat(timestamp.replace("Z", "+00:00")).astimezone(TORONTO)

    errors = []
    for name in changed_files_path.read_text(encoding="utf-8").splitlines():
        path = Path(name)
        if len(path.parts) != 3 or path.parts[0] != "model-output":
            continue
        match = FILE_NAME.fullmatch(path.name)
        if not match or not path.is_file():
            continue  # Other file checks are performed by Hubverse validation.

        reference_date = date.fromisoformat(match.group(1))
        if not (FIRST_ROUND <= reference_date <= LAST_ROUND):
            continue

        opening = datetime.combine(reference_date - timedelta(days=1), time.min, TORONTO)
        deadline = datetime.combine(reference_date, time(23, 30), TORONTO)
        if not opening <= submitted_at <= deadline:
            errors.append(
                f"{name}: pull request update at {submitted_at.isoformat()} is outside "
                f"the window {opening.isoformat()} through {deadline.isoformat()}"
            )

    if errors:
        raise SystemExit("\n".join(errors))
    print("2026-2027 submission cutoff check passed.")


if __name__ == "__main__":
    check(Path(sys.argv[1]), Path(sys.argv[2]))
