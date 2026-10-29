"""Check the documented Xcode phase against real resource synchronization."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class XcodeResourcesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        project = json.loads(subprocess.check_output([
            "plutil", "-convert", "json", "-o", "-",
            str(ROOT / "example/ios/Runner.xcodeproj/project.pbxproj"),
        ]))
        phases = [phase for phase in project["objects"].values()
                  if phase.get("name") == "Copy Aliyun Auth Resources"]
        if len(phases) != 1:
            raise AssertionError("example must contain exactly one Aliyun resource phase")
        cls.phase = phases[0]

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aliyun-resource-test-")
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.source = base / "products/ATAuthSDK_D.framework/ATAuthSDK.bundle"
        self.source.mkdir(parents=True)
        self.output = base / "target/Runner.app/ATAuthSDK.bundle"
        self.env = dict(os.environ, BUILT_PRODUCTS_DIR=str(base / "products"),
                        TARGET_BUILD_DIR=str(base / "target"),
                        UNLOCALIZED_RESOURCES_FOLDER_PATH="Runner.app")

    def run_script(self):
        return subprocess.run(["/bin/sh", "-c", self.phase["shellScript"]],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def test_readme_publishes_the_tested_script_and_build_paths(self):
        readme = (ROOT / "README.md").read_text()
        self.assertIn("```sh\n" + self.phase["shellScript"] + "```", readme)
        self.assertEqual(self.phase["inputPaths"],
                         ["$(BUILT_PRODUCTS_DIR)/ATAuthSDK_D.framework/ATAuthSDK.bundle"])
        self.assertEqual(self.phase["outputPaths"],
                         ["$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/ATAuthSDK.bundle"])

    def test_updated_resources_replace_old_icons_in_main_bundle(self):
        (self.source / "current.png").write_bytes(b"current icon")
        self.output.mkdir(parents=True)
        (self.output / "removed.png").write_bytes(b"old icon")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.output / "current.png").read_bytes(), b"current icon")
        self.assertFalse((self.output / "removed.png").exists())

    def test_missing_sdk_resource_bundle_fails_without_erasing_previous_copy(self):
        self.source.rmdir()
        self.output.mkdir(parents=True)
        (self.output / "keep.png").write_bytes(b"previous icon")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ATAuthSDK.bundle missing", result.stderr)
        self.assertEqual((self.output / "keep.png").read_bytes(), b"previous icon")


if __name__ == "__main__":
    unittest.main()
