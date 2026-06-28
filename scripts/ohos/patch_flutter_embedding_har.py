#!/usr/bin/env python3

import gzip
import io
import sys
import tarfile
import time
from pathlib import Path


BEFORE = """    const argsMap = call.args as Map<string, string>;
    const currentUri: string = argsMap.get('uri') ?? '';
"""

AFTER = """    const uriArg = call.argument('uri');
    const currentUri: string = typeof uriArg === 'string' ? uriArg : '';
"""

TARGET_SUFFIX = "package/src/main/ets/embedding/engine/systemchannels/NavigationChannel.ets"


def patch_har(path: Path) -> bool:
    raw = path.read_bytes()
    data = gzip.decompress(raw)
    src = io.BytesIO(data)
    tf = tarfile.open(fileobj=src, mode="r:")
    out = io.BytesIO()
    patched = False

    with tarfile.open(fileobj=out, mode="w") as ntf:
      for member in tf.getmembers():
        extracted = tf.extractfile(member) if member.isfile() else None
        payload = extracted.read() if extracted else None
        if member.name.endswith(TARGET_SUFFIX) and payload is not None:
            try:
                text = payload.decode("utf-8")
            except UnicodeDecodeError as exc:
                raise RuntimeError(
                    f"failed to decode NavigationChannel.ets in {path}: {exc}"
                ) from exc
            if AFTER in text:
                patched = True
            elif BEFORE in text:
                text = text.replace(BEFORE, AFTER, 1)
                payload = text.encode("utf-8")
                member.size = len(payload)
                member.mtime = int(time.time())
                patched = True
            else:
                raise RuntimeError(
                    f"expected NavigationChannel snippet not found in {path}"
                )
        ntf.addfile(member, io.BytesIO(payload) if payload is not None else None)

    if not patched:
        raise RuntimeError(f"NavigationChannel.ets not found in {path}")

    out.seek(0)
    path.write_bytes(gzip.compress(out.getvalue()))
    return True


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: patch_flutter_embedding_har.py <har> [<har> ...]", file=sys.stderr)
        return 2

    for arg in sys.argv[1:]:
        path = Path(arg)
        if not path.exists():
            continue
        patch_har(path)
        print(f"patched {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
