#!/usr/bin/env python3
"""List this app's recent TestFlight builds with the local App Store Connect API key.

Reads ~/.appstoreconnect/config.json (key_id, issuer_id, key_path). The private key
stays on disk; it is passed to openssl by path and never printed.
"""
import base64, json, os, subprocess, sys, time, urllib.request
from pathlib import Path

APP_ID = json.loads((Path(__file__).resolve().parents[1] / "ios/Release.json").read_text())["app_store_app_id"]

def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

def der_to_raw(signature: bytes) -> bytes:
    # ECDSA DER: 30 len 02 lenR R 02 lenS S -> fixed 32-byte r || s for JWS ES256.
    assert signature[0] == 0x30
    index = 2
    parts = []
    for _ in range(2):
        assert signature[index] == 0x02
        length = signature[index + 1]
        value = signature[index + 2:index + 2 + length]
        parts.append(value.lstrip(b"\0").rjust(32, b"\0"))
        index += 2 + length
    return b"".join(parts)

def token(config: dict) -> str:
    key = os.path.expanduser(config["key_path"])
    header = {"alg": "ES256", "kid": config["key_id"], "typ": "JWT"}
    now = int(time.time())
    claims = {"iss": config["issuer_id"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing_input = b64(json.dumps(header).encode()) + "." + b64(json.dumps(claims).encode())
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key], input=signing_input.encode(), capture_output=True, check=True).stdout
    return signing_input + "." + b64(der_to_raw(der))

def get(path: str, bearer: str) -> dict:
    request = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, headers={"Authorization": "Bearer " + bearer})
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)

def main() -> int:
    config = json.loads(Path("~/.appstoreconnect/config.json").expanduser().read_text())
    bearer = token(config)
    builds = get(f"/v1/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=5&include=preReleaseVersion,buildBetaDetail", bearer)
    versions = {item["id"]: item["attributes"].get("version") for item in builds.get("included", []) if item["type"] == "preReleaseVersions"}
    details = {item["id"]: item["attributes"] for item in builds.get("included", []) if item["type"] == "buildBetaDetails"}
    for build in builds["data"]:
        attributes = build["attributes"]
        version = versions.get(build["relationships"]["preReleaseVersion"]["data"]["id"], "?")
        beta = details.get(build["relationships"]["buildBetaDetail"]["data"]["id"], {})
        print(f'{version} ({attributes["version"]})  processing={attributes["processingState"]}  internal={beta.get("internalBuildState", "?")}  external={beta.get("externalBuildState", "?")}  uploaded={attributes["uploadedDate"]}')
    return 0

if __name__ == "__main__":
    sys.exit(main())
