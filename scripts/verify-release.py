#!/usr/bin/env python3
"""Verify public release material. No signing key or third-party Python package is used."""
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import zipfile

folder = Path(sys.argv[1])
source = sys.argv[2] if len(sys.argv) > 2 else subprocess.check_output(["git", "rev-parse", "HEAD^"], text=True).strip()
envelope_bytes = (folder / "update.json").read_bytes()
assert len(envelope_bytes) <= 65536
envelope = json.loads(envelope_bytes)
assert envelope["schema"] == 1
payload = base64.b64decode(envelope["payload"], validate=True)
signature = base64.b64decode(envelope["signature"], validate=True)
assert len(payload) <= 16384 and len(signature) == 64
trust_source = Path("Sources/WeekletCore/Updates.swift").read_text()
public_key = base64.b64decode(re.search(r'publicKeyBase64 = "([A-Za-z0-9+/=]+)"', trust_source)[1], validate=True)
assert len(public_key) == 32
if sys.platform == "darwin":
    verifier = os.environ.get("WEEKLET_RELEASE_TOOL")
    assert verifier, "Set WEEKLET_RELEASE_TOOL to the compiled native release tool"
    subprocess.run([verifier, "verify", str(folder / "update.json")], check=True)
else:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        (root / "key.der").write_bytes(bytes.fromhex("302a300506032b6570032100") + public_key)
        (root / "payload").write_bytes(payload)
        (root / "signature").write_bytes(signature)
        subprocess.run(["openssl", "pkeyutl", "-verify", "-pubin", "-keyform", "DER", "-inkey", str(root / "key.der"),
                        "-rawin", "-in", str(root / "payload"), "-sigfile", str(root / "signature")], check=True, capture_output=True)
release = json.loads(payload)
assert release["schema"] == 1 and type(release["build"]) is int and release["build"] > 0
assert re.fullmatch(r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)", release["version"])
assert re.fullmatch(r"[0-9a-f]{40}", release["sourceCommit"]) and release["sourceCommit"] == source
assert release["architecture"] in ("arm64", "x86_64", "universal")
assert release["minimumSystemVersion"] == "14.0.0"
name = "Weeklet-macOS-" + release["architecture"] + ".zip"
expected_url = "https://github.com/mgalli97/weeklet/releases/download/v" + release["version"] + "/" + name
assert release["archiveURL"] == expected_url
archive = folder / name
assert archive.stat().st_size == release["archiveSize"] and 0 < archive.stat().st_size <= 67108864
digest = hashlib.sha256()
with archive.open("rb") as stream:
    for chunk in iter(lambda: stream.read(1048576), b""):
        digest.update(chunk)
assert digest.hexdigest() == release["archiveSHA256"]
with zipfile.ZipFile(archive) as zipped:
    entries = zipped.infolist()
    assert 0 < len(entries) <= 4096 and sum(e.file_size for e in entries) <= 268435456
    seen = set()
    for entry in entries:
        name_in_zip = entry.filename
        assert name_in_zip.startswith("Weeklet.app/") and "\\" not in name_in_zip and ":" not in name_in_zip
        assert all(part not in ("", ".", "..") for part in name_in_zip.rstrip("/").split("/"))
        assert name_in_zip.lower() not in seen
        seen.add(name_in_zip.lower())
        assert stat.S_IFMT(entry.external_attr >> 16) in (0, stat.S_IFREG, stat.S_IFDIR)
        assert not entry.flag_bits & 1 and entry.compress_type in (0, 8)
    info_data = zipped.read("Weeklet.app/Contents/Info.plist")
    assert len(info_data) <= 65536
    info = plistlib.loads(info_data)
    assert info["CFBundleIdentifier"] == "com.mgalli97.weeklet" and info["CFBundleExecutable"] == "Weeklet"
    assert info["CFBundleShortVersionString"] == release["version"] and info["CFBundleVersion"] == str(release["build"])
    for executable in ("Weeklet", "WeekletInstaller"):
        entry = zipped.getinfo("Weeklet.app/Contents/MacOS/" + executable)
        assert entry.external_attr >> 16 & 0o111
        binary = zipped.read(entry)
        assert b"/Users/" not in binary, "Personal build path found in executable"
metadata = {"tag": "v" + release["version"], "version": release["version"], "source": source, "archive": archive.name}
(folder / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
print("Verified signed Weeklet release " + release["version"])
