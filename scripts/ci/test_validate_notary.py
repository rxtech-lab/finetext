import json
import os
import pathlib
import subprocess
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).with_name("validate-notary.sh")


class NotaryCredentialTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = pathlib.Path(self.directory.name)
        xcrun = self.path / "xcrun"
        xcrun.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
pathlib.Path(os.environ["NOTARY_CALL"]).write_text(json.dumps(sys.argv[1:]))
print("private submission history")
sys.exit(int(os.environ.get("NOTARY_EXIT", "0")))
''')
        xcrun.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{self.path}:{os.environ['PATH']}",
            "APPLE_ID": "rxlab@example.com",
            "APPLE_ID_PWD": "test-app-password",
            "APPLE_TEAM_ID": "T7GYB573Y6",
            "NOTARY_CALL": str(self.path / "call.json"),
        }

    def validate(self):
        return subprocess.run(["bash", str(SCRIPT)], env=self.env,
                              capture_output=True, text=True)

    def test_authenticates_with_rxlab_team_without_printing_credentials_or_history(self):
        result = self.validate()
        self.assertEqual(result.returncode, 0, result.stderr)
        call = json.loads((self.path / "call.json").read_text())
        self.assertEqual(call, ["notarytool", "history", "--apple-id", "rxlab@example.com",
                                "--password", "test-app-password", "--team-id",
                                "T7GYB573Y6", "--output-format", "json"])
        for sensitive in ("private submission history", "test-app-password", "rxlab@example.com"):
            self.assertNotIn(sensitive, result.stdout + result.stderr)

    def test_missing_credentials_fail_before_contacting_apple(self):
        for field in ("APPLE_ID", "APPLE_ID_PWD", "APPLE_TEAM_ID"):
            with self.subTest(field=field):
                value = self.env.pop(field)
                self.assertNotEqual(self.validate().returncode, 0)
                self.assertFalse((self.path / "call.json").exists())
                self.env[field] = value

    def test_rejects_personal_team_before_contacting_apple(self):
        self.env["APPLE_TEAM_ID"] = "P9KK452K8P"
        self.assertNotEqual(self.validate().returncode, 0)
        self.assertFalse((self.path / "call.json").exists())

    def test_authentication_failure_fails_ci(self):
        self.env["NOTARY_EXIT"] = "1"
        result = self.validate()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("credentials validated", result.stdout)


if __name__ == "__main__":
    unittest.main()
