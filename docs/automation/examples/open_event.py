"""Opens a TuitMate webhook event (Python 3.8+, `pip install cryptography`).

    TUITMATE_KEY=<base64 key> python open_event.py body.json [signature-header]
"""
import base64
import binascii
import hashlib
import hmac
import json
import os
import re
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM


def parse_key(text):
    t = re.sub(r"\s+", "", text or "")
    if re.fullmatch(r"[0-9a-fA-F]{64}", t):
        key = binascii.unhexlify(t)
    else:
        t = t.replace("-", "+").replace("_", "/")
        key = base64.b64decode(t + "=" * (-len(t) % 4))
    if len(key) != 32:
        raise ValueError("TUITMATE_KEY must be 32 bytes (AES-256)")
    return key


def verify_signature(raw_body: bytes, header: str, key: bytes) -> bool:
    expected = "sha256=" + hmac.new(key, raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header or "")


def open_event(envelope: dict, key: bytes) -> dict:
    if envelope.get("v") != 1:
        raise ValueError("unknown version")
    if envelope.get("enc") == "none":
        return {k: envelope.get(k) for k in ("v", "id", "event", "sent_at", "payload")}
    if envelope.get("enc") != "A256GCM":
        raise ValueError("unknown enc")
    aad = f"tuitmate.v1|{envelope['id']}|{envelope['event']}|{envelope['sent_at']}".encode()
    # AESGCM expects the 16-byte tag appended to the ciphertext, which is how TuitMate sends it.
    clear = AESGCM(key).decrypt(base64.b64decode(envelope["iv"]), base64.b64decode(envelope["data"]), aad)
    return json.loads(clear)


if __name__ == "__main__":
    raw = open(sys.argv[1], "rb").read()
    key = parse_key(os.environ.get("TUITMATE_KEY"))
    if len(sys.argv) > 2 and not verify_signature(raw, sys.argv[2], key):
        sys.exit("bad signature")
    sys.stdout.write(json.dumps(open_event(json.loads(raw), key)))
