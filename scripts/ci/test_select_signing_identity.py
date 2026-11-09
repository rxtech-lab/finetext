import importlib.util
import pathlib
import unittest


spec = importlib.util.spec_from_file_location(
    "identity", pathlib.Path(__file__).with_name("select-signing-identity.py")
)
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)

RXLAB = '1) ' + 'A' * 40 + ' "Developer ID Application: Rxlab LIMITED (T7GYB573Y6)"'
PERSONAL = '2) ' + 'B' * 40 + ' "Developer ID Application: Qiwei Li (P9KK452K8P)"'


class IdentityTests(unittest.TestCase):
    def test_selects_rxlab_with_both_teams_installed(self):
        self.assertEqual(identity.select_identity(PERSONAL + '\n' + RXLAB, "T7GYB573Y6"), 'A' * 40)

    def test_rejects_other_team(self):
        with self.assertRaisesRegex(ValueError, "found 0"):
            identity.select_identity(PERSONAL, "T7GYB573Y6")

    def test_rejects_development_certificate(self):
        with self.assertRaisesRegex(ValueError, "found 0"):
            identity.select_identity(RXLAB.replace("Developer ID Application", "Apple Development"), "T7GYB573Y6")

    def test_rejects_ambiguous_certificates(self):
        with self.assertRaisesRegex(ValueError, "found 2"):
            identity.select_identity(RXLAB + '\n' + RXLAB.replace('A' * 40, 'C' * 40), "T7GYB573Y6")

    def test_rejects_missing_team(self):
        with self.assertRaisesRegex(ValueError, "APPLE_TEAM_ID"):
            identity.select_identity(RXLAB, "")


if __name__ == "__main__":
    unittest.main()
