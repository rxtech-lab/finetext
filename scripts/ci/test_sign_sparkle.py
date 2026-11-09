import json
import os
import pathlib
import plistlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = pathlib.Path(self.directory.name)
        self.entitlements = plistlib.loads(
            (ROOT / "Configuration/FineText.entitlements").read_bytes()
        )
        self.entitlements = plistlib.loads(plistlib.dumps(self.entitlements).replace(
            b"$(PRODUCT_BUNDLE_IDENTIFIER)", b"app.rxlab.finetext"
        ))
        # Exercise the full signing script without a Developer ID certificate.
        codesign = self.path / "codesign"
        codesign.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
with open(os.environ["SIGNING_CALLS"], "a") as calls:
    calls.write(json.dumps(sys.argv[1:]) + "\\n")
if "-d" in sys.argv:
    sys.stdout.buffer.write(pathlib.Path(os.environ["SIGNED_ENTITLEMENTS"]).read_bytes())
''')
        codesign.chmod(0o755)

    def sign(self):
        fixture = self.path / "signed.plist"
        fixture.write_bytes(plistlib.dumps(self.entitlements))
        return subprocess.run(
            ["bash", str(ROOT / "scripts/ci/sign-sparkle.sh")],
            env={**os.environ, "PATH": f"{self.path}:{os.environ['PATH']}",
                 "SIGNING_CERTIFICATE_NAME": "Test identity",
                 "SIGNED_ENTITLEMENTS": str(fixture),
                 "SIGNING_CALLS": str(self.path / "calls.jsonl")},
            capture_output=True, text=True,
        )

    def test_accepts_configured_entitlements_and_preserves_metadata(self):
        result = self.sign()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in (self.path / "calls.jsonl").read_text().splitlines()]
        signing = [call for call in calls if "--sign" in call]
        self.assertEqual(len(signing), 6)
        for call in signing:
            preserve = call[-1].endswith(("Downloader.xpc", "FineText.app"))
            self.assertEqual("--preserve-metadata=entitlements" in call, preserve)
        self.assertTrue(any(call[:4] == ["--verify", "--deep", "--strict", "--verbose=2"] for call in calls))

    def test_rejects_sandbox_enabled(self):
        self.entitlements["com.apple.security.app-sandbox"] = True
        result = self.sign()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("non-sandboxed app entitlements", result.stderr)

    def test_rejects_missing_sandbox_setting(self):
        del self.entitlements["com.apple.security.app-sandbox"]
        self.assertNotEqual(self.sign().returncode, 0)

    def test_rejects_missing_sparkle_lookup(self):
        self.entitlements["com.apple.security.temporary-exception.mach-lookup.global-name"] = []
        result = self.sign()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing Sparkle installer", result.stderr)


if __name__ == "__main__":
    unittest.main()
