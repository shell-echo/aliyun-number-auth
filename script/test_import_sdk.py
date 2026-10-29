"""Exercise SDK import against disposable vendor ZIPs, never the real SDKs."""

import io
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import unittest
import uuid
import zipfile


SCRIPT = Path(__file__).with_name("import-sdk.sh")
ANDROID_CLASSES = {
    "PhoneNumberAuthHelper": "setAuthSDKInfo checkEnvAvailable accelerateVerify "
    "accelerateLoginPage getVerifyToken getLoginToken quitLoginPage quitPrivacyPage "
    "setProtocolChecked queryCheckBoxIsChecked privacyAnimationStart "
    "checkBoxAnimationStart hideLoginLoading getVersion expandAuthPageCheckedScope "
    "setUIClickListener setAuthListener userControlAuthPageCancel "
    "removeAuthRegisterXmlConfig removeAuthRegisterViewConfig "
    "removePrivacyAuthRegisterViewConfig removePrivacyRegisterXmlConfig SERVICE_TYPE_AUTH",
    "TokenResultListener": "",
    "PreLoginResultListener": "",
    "model/TokenRet": "fromJson",
    "ResultCode": "",
}
IOS_METHODS = (
    "sharedInstance setAuthSDKInfo checkEnvAvailableWithAuthType "
    "accelerateVerifyWithTimeout accelerateLoginPageWithTimeout "
    "getVerifyTokenWithTimeout getLoginTokenWithTimeout cancelLoginVCAnimated "
    "setCheckboxIsChecked queryCheckBoxIsChecked privacyAnimationStart "
    "checkboxAnimationStart closePrivactAlertView hideLoginLoading getVersion"
)


def zip_bytes(files):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        for name, data in files.items():
            archive.writestr(name, data)
    return output.getvalue()


class ImportSdkTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Real Mach-O/dSYM fixtures let the importer exercise dwarfdump and UUID
        # matching without relying on vendor code or fake production symbols.
        cls.vendor_temp = tempfile.TemporaryDirectory(prefix="aliyun-symbol-fixture-")
        cls.addClassCleanup(cls.vendor_temp.cleanup)
        root = Path(cls.vendor_temp.name)
        source = root / "fixture.c"
        source.write_text("int auth_fixture(void) { return 1; }\n")
        binary = root / "ATAuthSDK_D"
        sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
        subprocess.run(["xcrun", "clang", "-g", "-dynamiclib", "-target", "arm64-apple-ios13.0",
                        "-isysroot", sdk, str(source), "-o", str(binary)], check=True, capture_output=True)
        dsym = root / "ATAuthSDK_D.framework.dSYM"
        subprocess.run(["xcrun", "dsymutil", str(binary), "-o", str(dsym)], check=True, capture_output=True)
        cls.binary = binary.read_bytes()
        cls.symbols = {str(p.relative_to(dsym)): p.read_bytes() for p in dsym.rglob("*") if p.is_file()}

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="aliyun-import-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "plugin with spaces"
        (self.root / "script").mkdir(parents=True)
        shutil.copy2(SCRIPT, self.root / "script/import-sdk.sh")
        shutil.copy2(SCRIPT.with_name("package_ios_sdk.py"), self.root / "script/package_ios_sdk.py")
        (self.root / "sdk").mkdir()
        self.android = self.root / "android/libs-maven/com/aliyun/atauth"
        self.ios = self.root / "ios/aliyun_number_auth/Frameworks"
        for target in [self.android, self.ios]:
            target.mkdir(parents=True)
            (target / "old-sdk").write_bytes(b"original SDK")
        self.gradle = self.root / "android/build.gradle.kts"
        self.gradle.write_text("\n".join(
            f'    implementation("com.aliyun.atauth:{artifact}:1.0.0@aar")'
            for artifact in ["auth_number_product", "main", "logger"]
        ) + "\n")
        self.before = self.snapshot()
        self.make_archives()

    def snapshot(self):
        return {
            str(path.relative_to(self.root)): path.read_bytes()
            for parent in [self.root / "android", self.root / "ios"]
            for path in parent.rglob("*") if path.is_file()
        }

    def make_archives(self, invalid_ios=False, invalid_aar=False, missing_dsym=False, mismatched_dsym=False):
        classes = zip_bytes({
            f"com/mobile/auth/gatewayauth/{name}.class": value
            for name, value in ANDROID_CLASSES.items()
        })
        aar = zip_bytes({"classes.jar": classes})
        android_files = {
            "SDK/auth_number_product-2.14.23.aar": aar,
            "SDK/main-2.2.3.aar": aar,
            ("SDK/unparseable.aar" if invalid_aar else "SDK/logger-2.2.2.aar"): aar,
        }
        (self.root / "sdk/numberAuthSDK_APP_Android_v2.14.23.zip").write_bytes(
            zip_bytes(android_files)
        )
        base = "xcframeworks/ATAuthSDK_D.xcframework/ios-arm64/ATAuthSDK_D.framework"
        ios_files = {
            f"{base}/ATAuthSDK_D": self.binary,
            f"{base}/Headers/ATAuthSDK.h": b"// test SDK umbrella header",
            f"{base}/PrivacyInfo.xcprivacy": b"vendor privacy manifest",
            "xcframeworks/ATAuthSDK_D.xcframework/Info.plist": plistlib.dumps({
                "AvailableLibraries": [{"LibraryIdentifier": "ios-arm64", "LibraryPath": "ATAuthSDK_D.framework",
                                        "SupportedArchitectures": ["arm64"], "SupportedPlatform": "ios"}],
                "XCFrameworkFormatVersion": "1.0",
            }),
        }
        ios_files[f"{base}/Headers/TXCommonHandler.h"] = (
            "missing required methods" if invalid_ios else IOS_METHODS
        )
        ios_files[f"{base}/ATAuthSDK.bundle/icon.png"] = b"vendor icon"
        if not missing_dsym:
            for name, data in self.symbols.items():
                if mismatched_dsym and name.endswith("DWARF/ATAuthSDK_D"):
                    # Change only LC_UUID in the disposable symbol fixture.
                    binary_uuid = re.search(r"UUID: (\S+)", subprocess.check_output(
                        ["xcrun", "dwarfdump", "--uuid", str(Path(self.vendor_temp.name) / "ATAuthSDK_D")], text=True
                    )).group(1)
                    data = data.replace(uuid.UUID(binary_uuid).bytes, b"\x11" * 16, 1)
                ios_files[f"frameworks/ATAuthSDK_D.framework.dSYM/{name}"] = data
        (self.root / "sdk/numberAuthSDK_APP_iOS_v2.14.19_dynamic.zip").write_bytes(
            zip_bytes(ios_files)
        )

    def run_import(self, env=None):
        return subprocess.run(
            ["bash", str(self.root / "script/import-sdk.sh")],
            cwd=self.root, env=env, capture_output=True, text=True, timeout=30,
        )

    def test_invalid_ios_leaves_both_platforms_unchanged(self):
        self.make_archives(invalid_ios=True)
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.snapshot(), self.before)

    def test_invalid_later_aar_preserves_previous_sdk(self):
        self.make_archives(invalid_aar=True)
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.snapshot(), self.before)

    def test_unrelated_old_temp_directories_are_untouched(self):
        for name in ["android_tmp", "ios_tmp"]:
            path = self.root / "sdk" / name
            path.mkdir()
            (path / "keep").write_bytes(b"user data")
        self.run_import()
        for name in ["android_tmp", "ios_tmp"]:
            self.assertEqual((self.root / "sdk" / name / "keep").read_bytes(), b"user data")

    def test_success_updates_pins_and_preserves_resources(self):
        result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        for artifact, version in [("auth_number_product", "2.14.23"), ("main", "2.2.3"), ("logger", "2.2.2")]:
            self.assertIn(f"{artifact}:{version}@aar", self.gradle.read_text())
            self.assertTrue((self.android / artifact / version / f"{artifact}-{version}.aar").is_file())
        self.assertFalse((self.android / "old-sdk").exists())
        self.assertFalse((self.ios / "old-sdk").exists())
        framework = self.ios / "ATAuthSDK_D.xcframework/ios-arm64/ATAuthSDK_D.framework"
        self.assertEqual((framework / "ATAuthSDK.bundle/icon.png").read_bytes(), b"vendor icon")
        self.assertEqual((framework / "PrivacyInfo.xcprivacy").read_bytes(), b"vendor privacy manifest")
        self.assertIn("framework module ATAuthSDK_D", (framework / "Modules/module.modulemap").read_text())
        packaged = framework.parent / "dSYMs/ATAuthSDK_D.framework.dSYM/Contents/Resources/DWARF/ATAuthSDK_D"
        self.assertEqual(packaged.read_bytes(), self.symbols["Contents/Resources/DWARF/ATAuthSDK_D"])
        info = plistlib.loads((framework.parent.parent / "Info.plist").read_bytes())
        self.assertEqual(info["AvailableLibraries"][0]["DebugSymbolsPath"], "dSYMs")

    def test_missing_dsym_preserves_previous_sdk(self):
        self.make_archives(missing_dsym=True)
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.snapshot(), self.before)

    def test_uuid_mismatch_preserves_previous_sdk(self):
        self.make_archives(mismatched_dsym=True)
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("UUID mismatch", result.stderr)
        self.assertEqual(self.snapshot(), self.before)

    def test_publish_failure_rolls_back_files_and_gradle(self):
        bin_dir = self.root / "fake-bin"
        bin_dir.mkdir()
        wrapper = bin_dir / "mv"
        wrapper.write_text('#!/bin/bash\ncase "$1" in */staged/Frameworks) exit 71;; esac\nexec /bin/mv "$@"\n')
        wrapper.chmod(0o755)
        env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}")
        result = self.run_import(env=env)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.snapshot(), self.before)

    def test_term_during_publish_rolls_back_files_and_gradle(self):
        bin_dir = self.root / "fake-bin"
        bin_dir.mkdir()
        wrapper = bin_dir / "mv"
        wrapper.write_text('#!/bin/bash\ncase "$1" in */staged/Frameworks) kill -TERM "$PPID"; exit 0;; esac\nexec /bin/mv "$@"\n')
        wrapper.chmod(0o755)
        result = self.run_import(env=dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}"))
        self.assertEqual(result.returncode, 143, result.stdout + result.stderr)
        self.assertEqual(self.snapshot(), self.before)
        self.assertFalse((self.root / "sdk/.import-sdk.lock").exists())

    def test_existing_import_lock_is_not_removed(self):
        lock = self.root / "sdk/.import-sdk.lock"
        lock.mkdir()
        (lock / "owner").write_bytes(b"another import")
        result = self.run_import()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((lock / "owner").read_bytes(), b"another import")
        self.assertEqual(self.snapshot(), self.before)

    def test_reimport_is_idempotent(self):
        first = self.run_import()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        installed = self.snapshot()
        second = self.run_import()
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertEqual(self.snapshot(), installed)

    def test_ad_hoc_signature_is_valid_after_module_map_is_added(self):
        archive_path = self.root / "sdk/numberAuthSDK_APP_iOS_v2.14.19_dynamic.zip"
        with zipfile.ZipFile(archive_path) as archive:
            files = {name: archive.read(name) for name in archive.namelist()}
        prefix = "xcframeworks/ATAuthSDK_D.xcframework/ios-arm64/ATAuthSDK_D.framework/"
        framework = self.root / "signing-fixture/ATAuthSDK_D.framework"
        for name, data in files.items():
            if name.startswith(prefix):
                path = framework / name[len(prefix):]
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
        (framework / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "test.aliyun.auth", "CFBundlePackageType": "FMWK",
            "CFBundleExecutable": "ATAuthSDK_D", "CFBundleVersion": "1",
        }))
        subprocess.run(["codesign", "--force", "--sign", "-", str(framework)], check=True, capture_output=True)
        for path in framework.rglob("*"):
            if path.is_file():
                files[prefix + str(path.relative_to(framework))] = path.read_bytes()
        archive_path.write_bytes(zip_bytes(files))

        result = self.run_import()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        packaged = self.ios / "ATAuthSDK_D.xcframework/ios-arm64/ATAuthSDK_D.framework"
        checked = subprocess.run(["codesign", "--verify", "--strict", str(packaged)], capture_output=True, text=True)
        self.assertEqual(checked.returncode, 0, checked.stderr)


if __name__ == "__main__":
    unittest.main()
