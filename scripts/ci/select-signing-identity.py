"""Select a valid Developer ID identity for the release team, never another team."""

import os
import re
import subprocess
from pathlib import Path


def select_identity(identities, team):
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise ValueError("APPLE_TEAM_ID must be a ten-character Apple team identifier")
    matches = re.findall(
        r'\b([A-Fa-f0-9]{40}) "Developer ID Application: [^"\n]+ \('
        + re.escape(team) + r'\)"', identities
    )
    matches = list(dict.fromkeys(matches))
    if len(matches) != 1:
        raise ValueError(
            f"Expected one valid Developer ID Application identity for team {team}; "
            f"found {len(matches)}. Check BUILD_CERTIFICATE_BASE64 and P12_PASSWORD "
            "and the runner keychain."
        )
    return matches[0]


if __name__ == "__main__":
    identities = subprocess.check_output(
        ["security", "find-identity", "-v", "-p", "codesigning"], text=True
    )
    identity = select_identity(identities, os.environ["APPLE_TEAM_ID"])
    with Path(os.environ["GITHUB_ENV"]).open("a") as environment:
        environment.write(f"SIGNING_CERTIFICATE_NAME={identity}\n")
    print(f"Selected Developer ID certificate for team {os.environ['APPLE_TEAM_ID']}")
