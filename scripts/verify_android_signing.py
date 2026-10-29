"""Verify the built APK and its pinned signing certificate before publishing."""

import os
from pathlib import Path
import re
import subprocess
import sys

from configure_android_signing import expected_fingerprint


def verify(apk):
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if not sdk:
        raise RuntimeError("Android-SDK nicht gefunden.")
    candidates = list((Path(sdk) / "build-tools").glob("*/apksigner"))
    if not candidates:
        raise RuntimeError("Android-apksigner nicht gefunden.")
    tool = max(candidates, key=lambda path: tuple(
        int(part) for part in re.findall(r"\d+", path.parent.name)))
    result = subprocess.run(
        [str(tool), "verify", "--verbose", "--print-certs", str(apk)],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError("APK-Signaturpruefung fehlgeschlagen.")
    # apksigner output contains only public certificate metadata.
    print("Android signing tool:", tool.parent.name)
    print(result.stdout, flush=True)
    certificates = re.findall(
        r"^Signer #\d+ certificate SHA-256 digest: ([0-9a-fA-F]+)$",
        result.stdout, flags=re.MULTILINE,
    )
    if [value.lower() for value in certificates] != [expected_fingerprint()]:
        raise RuntimeError("APK besitzt nicht das festgelegte Signaturzertifikat.")
    print("APK-Signatur geprueft. SHA-256:", certificates[0])


if __name__ == "__main__":
    try:
        verify(Path("build/app/outputs/flutter-apk/app-release.apk"))
    except (RuntimeError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
