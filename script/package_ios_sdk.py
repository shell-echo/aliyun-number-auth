"""Package the vendor's dynamic XCFramework with its matching device dSYM."""

import argparse
from pathlib import Path
import plistlib
import re
import shutil
import subprocess


def uuids(path):
    output = subprocess.check_output(
        ["xcrun", "dwarfdump", "--uuid", str(path)], text=True
    )
    result = {
        arch: uuid.upper()
        for uuid, arch in re.findall(r"UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)", output)
    }
    if not result:
        raise ValueError(f"no build UUID in {path}")
    return result


def package(source, dsym, destination):
    with (source / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    devices = [
        library for library in info["AvailableLibraries"]
        if library["SupportedPlatform"] == "ios"
        and not library.get("SupportedPlatformVariant")
    ]
    if len(devices) != 1 or devices[0]["LibraryIdentifier"] != "ios-arm64":
        raise ValueError("expected one ios-arm64 device slice")
    device = devices[0]
    if device["LibraryPath"] != "ATAuthSDK_D.framework":
        raise ValueError("expected the vendor's ATAuthSDK_D.framework")
    binary = source / device["LibraryIdentifier"] / device["LibraryPath"] / "ATAuthSDK_D"
    description = subprocess.check_output(["file", "-b", str(binary)], text=True)
    if "dynamically linked shared library" not in description:
        raise ValueError("ATAuthSDK_D must be the official dynamic library")
    symbols = dsym / "Contents/Resources/DWARF/ATAuthSDK_D"
    binary_uuids = uuids(binary)
    symbol_uuids = uuids(symbols)
    if binary_uuids != symbol_uuids:
        raise ValueError(f"vendor dSYM UUID mismatch: {binary_uuids} != {symbol_uuids}")
    if (source / "_CodeSignature").exists():
        raise ValueError("signed XCFramework needs an explicitly reviewed repackaging process")

    # Preserve vendor resources and DWARF. The supplied unsigned device binary
    # stays byte-for-byte intact; simulator resource signatures are resealed below.
    shutil.copytree(source, destination)
    for library in info["AvailableLibraries"]:
        framework = destination / library["LibraryIdentifier"] / library["LibraryPath"]
        signature = subprocess.run(["codesign", "--display", "--verbose=2", str(framework)],
                                   capture_output=True, text=True)
        signed = signature.returncode == 0
        if signed and "Signature=adhoc" not in signature.stderr:
            raise ValueError(f"refusing to alter an identity-signed vendor framework: {framework}")
        if not (framework / "Headers/ATAuthSDK.h").is_file():
            raise ValueError(f"missing public umbrella header: {framework}")
        # The official dynamic distribution targets Objective-C integration and
        # has no module map. Supply Swift's import metadata for every slice.
        modules = framework / "Modules"
        modules.mkdir(exist_ok=True)
        (modules / "module.modulemap").write_text(
            'framework module ATAuthSDK_D {\n'
            '  umbrella header "ATAuthSDK.h"\n'
            '  export *\n'
            '  module * { export * }\n'
            '}\n'
        )
        if signed:
            # The simulator framework is vendor ad-hoc signed. Its resource seal
            # must include the new module map; no credential or vendor identity
            # is used. Re-signing preserves its UUID and executable code.
            subprocess.run(["codesign", "--force", "--sign", "-", "--timestamp=none",
                            "--preserve-metadata=identifier,requirements,flags", str(framework)], check=True)
            subprocess.run(["codesign", "--verify", "--strict", str(framework)], check=True)
    debug_directory = destination / device["LibraryIdentifier"] / "dSYMs"
    debug_directory.mkdir()
    shutil.copytree(dsym, debug_directory / dsym.name)
    device["DebugSymbolsPath"] = "dSYMs"
    with (destination / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)
    print(f"✓ ATAuthSDK_D and vendor dSYM packaged: {binary_uuids}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("dsym", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    package(args.source, args.dsym, args.destination)
