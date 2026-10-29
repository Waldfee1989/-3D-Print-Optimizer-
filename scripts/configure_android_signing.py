"""Load the persistent Android key from one Actions secret; never generate keys in CI."""

import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys


class SigningError(Exception):
    pass


def expected_fingerprint():
    value = Path(__file__).with_name("android-signing.sha256").read_text().strip()
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise SigningError("Ungueltiger oeffentlicher Zertifikat-Fingerabdruck.")
    return value


def configure_gradle(text):
    """Patch only Flutter's generated Kotlin template; stop if its layout changes."""
    replacement = 'signingConfig = signingConfigs.getByName("release")'
    text, count = re.subn(
        r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
        replacement,
        text,
    )
    if count != 1 or "signingConfigs {" in text:
        raise SigningError("Flutter-Signaturvorlage hat sich geaendert; Build gestoppt.")
    imports = "import java.io.FileInputStream\nimport java.util.Properties\n\n"
    properties = '''val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
require(keystorePropertiesFile.isFile) { "Android signing configuration is missing" }
FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }

'''
    text, count = re.subn(r"(?m)^android\s*\{", properties + "android {", text)
    if count != 1:
        raise SigningError("Android-Konfiguration nicht eindeutig gefunden.")
    signing = '''    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = file(keystoreProperties.getProperty("storeFile"))
            storePassword = keystoreProperties.getProperty("storePassword")
            storeType = "PKCS12"
        }
    }

'''
    text, count = re.subn(r"(?m)^    buildTypes\s*\{", signing + "    buildTypes {", text)
    if count != 1:
        raise SigningError("Android-Buildtyp nicht eindeutig gefunden.")
    return imports + text


def configure(project, temporary):
    raw = os.environ.get("ANDROID_SIGNING_CONFIG", "")
    if not raw:
        raise SigningError("GitHub-Secret ANDROID_SIGNING_CONFIG fehlt. Keine APK erstellt.")
    try:
        config = json.loads(raw)
        if config.get("schema") != 1:
            raise ValueError()
        alias = config["key_alias"]
        password = config["store_password"]
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", alias):
            raise ValueError()
        if not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", password):
            raise ValueError()
        key_bytes = base64.b64decode(config["keystore_base64"], validate=True)
        if not 1000 <= len(key_bytes) <= 30000:
            raise ValueError()
    except (ValueError, TypeError, KeyError, AttributeError):
        raise SigningError("ANDROID_SIGNING_CONFIG ist unvollstaendig oder ungueltig.") from None

    if os.environ.get("GITHUB_ACTIONS") == "true":
        print("::add-mask::" + password, flush=True)
        print("::add-mask::" + config["keystore_base64"], flush=True)

    gradle = project / "android/app/build.gradle.kts"
    properties = project / "android/key.properties"
    if properties.exists():
        raise SigningError("Vorhandene key.properties wird nicht ueberschrieben.")
    patched = configure_gradle(gradle.read_text())
    directory = temporary / "optimizer-android-signing"
    directory.mkdir(mode=0o700)  # Never overwrite a previous signing directory.
    try:
        key = directory / "release.p12"
        with key.open("xb") as handle:
            os.chmod(key, 0o600)
            handle.write(key_bytes)
        # Password is passed via the environment, never as a process argument.
        env = dict(os.environ, OPTIMIZER_STORE_PASSWORD=password)
        env.pop("ANDROID_SIGNING_CONFIG", None)
        result = subprocess.run(
            ["keytool", "-exportcert", "-keystore", str(key), "-alias", alias,
             "-storepass:env", "OPTIMIZER_STORE_PASSWORD"],
            env=env, capture_output=True,
        )
        if result.returncode:
            raise SigningError("Signaturschluessel konnte nicht geoeffnet werden.")
        if hashlib.sha256(result.stdout).hexdigest() != expected_fingerprint():
            raise SigningError("Falscher Signaturschluessel; Zertifikat stimmt nicht ueberein.")
        content = (
            f"storeFile={key.resolve()}\nkeyAlias={alias}\n"
            f"storePassword={password}\nkeyPassword={password}\n"
        )
        with properties.open("x") as handle:
            os.chmod(properties, 0o600)
            handle.write(content)
        gradle.write_text(patched)
    except Exception:
        shutil.rmtree(directory)
        if properties.exists():
            properties.unlink()
        raise
    print("Fester Android-Signaturschluessel geladen und Zertifikat bestaetigt.")


if __name__ == "__main__":
    try:
        temporary = Path(os.environ["RUNNER_TEMP"])
        configure(Path.cwd(), temporary)
    except SigningError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except (OSError, KeyError):
        # Do not include exception details: malformed input could contain secrets.
        print("Android-Signierung fehlgeschlagen. Secret, Zertifikat und Buildvorlage pruefen.",
              file=sys.stderr)
        sys.exit(1)
