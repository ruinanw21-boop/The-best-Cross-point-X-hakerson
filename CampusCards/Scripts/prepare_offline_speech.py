"""Prepare the multilingual Whisper base resources before building CampusCards."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
from http.client import HTTPException
from pathlib import Path
import shutil
import sys
import tempfile
import time
from urllib.request import urlopen


SCRIPTS = Path(__file__).resolve().parent
BUNDLE = SCRIPTS.parent / "CampusCards" / "Resources" / "OfflineSpeech"
MODEL = "https://huggingface.co/argmaxinc/whisperkit-coreml/resolve/0f63a7800b00dd0226abd051b906c246e1907482"
TOKENIZER = "https://huggingface.co/openai/whisper-base/resolve/e37978b90ca9030d5170a5c07aadb050351a65bb"


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepare(entry, verify_only):
    expected, relative = entry.split("  ", 1)
    destination = BUNDLE / relative
    if destination.is_file() and sha256(destination) == expected:
        return destination.stat().st_size
    if verify_only:
        raise ValueError(f"Missing or invalid resource: {relative}")

    folder, name = relative.split("/", 1)
    url = f"{TOKENIZER}/{name}" if folder == "tokenizer" else f"{MODEL}/{relative}"
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Publish each file only after verification. Interrupted downloads can be retried.
    for attempt in range(3):
        with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as temp:
            temporary = Path(temp.name)
        try:
            with urlopen(url, timeout=120) as response, temporary.open("wb") as output:
                shutil.copyfileobj(response, output)
            if sha256(temporary) != expected:
                raise ValueError(f"SHA-256 mismatch: {relative}")
            temporary.replace(destination)
            return destination.stat().st_size
        except (OSError, HTTPException, ValueError):
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)
        finally:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="Check installed files without network access.")
    args = parser.parse_args()
    entries = (SCRIPTS / "offline-speech.sha256").read_text(encoding="utf-8").splitlines()
    with ThreadPoolExecutor(max_workers=4) as pool:
        total = sum(pool.map(lambda entry: prepare(entry, args.verify_only), entries))
    print(f"Verified {len(entries)} files ({total:,} bytes) in {BUNDLE}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, HTTPException, ValueError) as error:
        sys.exit(str(error))
