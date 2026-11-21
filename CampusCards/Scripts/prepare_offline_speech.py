"""Prepare the multilingual Whisper base resources before building CampusCards."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import ctypes
import hashlib
from http.client import HTTPException
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen


SCRIPTS = Path(__file__).resolve().parent
BUNDLE = SCRIPTS.parent / "CampusCards" / "Resources" / "OfflineSpeech"
SIMULATOR_BUNDLE = BUNDLE.parent / "Simulator" / "OfflineSpeech"
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


def prepare_simulator(entries):
    components = ("AudioEncoder.mlmodelc", "TextDecoder.mlmodelc")
    model = "openai_whisper-base"
    SIMULATOR_BUNDLE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".speech-", dir=SIMULATOR_BUNDLE.parent) as work:
        staging = Path(work) / "OfflineSpeech"
        staging.mkdir()
        (staging / ".gitkeep").touch()
        for entry in entries:
            relative = Path(entry.split("  ", 1)[1])
            if relative.parts[0] == model and relative.parts[1] in components:
                continue
            destination = staging / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(BUNDLE / relative, destination)

        compiler_output = Path(work) / "compiled"
        compiler_output.mkdir()
        for component in components:
            spec = BUNDLE / model / component / "model.mlmodel"
            subprocess.run(["xcrun", "--sdk", "iphonesimulator", "coremlcompiler",
                            "compile", str(spec), str(compiler_output)], check=True)
            compiled = compiler_output / "model.mlmodelc"
            for required in ("coremldata.bin", "weights/weight.bin"):
                if not (compiled / required).is_file() or not (compiled / required).stat().st_size:
                    raise ValueError(f"Incomplete simulator compilation of {component}: {required}")
            compiled.rename(staging / model / component)

        # On macOS a directory exchange publishes the complete pair atomically,
        # including on retries or concurrent prepares. The old tree is now in work.
        rename_swap = 0x00000002  # RENAME_SWAP in Darwin's <stdio.h>
        exchange = ctypes.CDLL(None, use_errno=True).renamex_np
        exchange.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
        exchange.restype = ctypes.c_int
        if exchange(os.fsencode(staging), os.fsencode(SIMULATOR_BUNDLE), rename_swap) != 0:
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error), SIMULATOR_BUNDLE)
    print(f"Prepared simulator models in {SIMULATOR_BUNDLE}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-only", action="store_true", help="Check installed files without network access.")
    args = parser.parse_args()
    entries = (SCRIPTS / "offline-speech.sha256").read_text(encoding="utf-8").splitlines()
    with ThreadPoolExecutor(max_workers=4) as pool:
        total = sum(pool.map(lambda entry: prepare(entry, args.verify_only), entries))
    print(f"Verified {len(entries)} files ({total:,} bytes) in {BUNDLE}")
    if sys.platform == "darwin" and not args.verify_only:
        prepare_simulator(entries)


if __name__ == "__main__":
    try:
        main()
    except (OSError, HTTPException, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
