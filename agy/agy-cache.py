#!/usr/bin/env python3
"""Read how much of an agy conversation's last model call came from cache.

Usage: agy-cache.py <conversation-id>
Prints the hit percentage of the conversation's latest model call, or nothing
at all: a missing or locked database, a format this
script does not recognise, or any other error prints nothing, so the status
line drops the segment rather than show a wrong number.

agy (the Antigravity CLI) keeps each conversation in
~/.gemini/antigravity-cli/conversations/<id>.db (override the folder with
AGY_CONVERSATIONS_DIR). The database is SQLite; each row of `steps` has a
`metadata` blob in protobuf wire format with no published schema. The fields
read here were identified by decoding real conversations, so an agy update
can move them:

  metadata.9      usage of a model call (only model calls have it)
  metadata.9.2    input tokens not read from cache
  metadata.9.5    input tokens read from cache

The newest step that has field 9 is the last call. Its 9.2 must be present as
a plain integer; 9.5 may be absent, which protobuf does for a zero, so a call
with nothing cached reads 0%. A newer step that does not parse, or a call
without 9.2, stops the search with nothing printed, rather than fall back to
an older call's number.
"""
import os
import pathlib
import re
import sqlite3
import sys

SCAN = 400  # most recent steps searched for a model call


def varint(b, i):
    v = s = 0
    while True:
        c = b[i]
        i += 1
        v |= (c & 0x7F) << s
        s += 7
        if c < 0x80:
            return v, i
        if s > 63:
            raise ValueError("varint too long")


def fields(b):
    """Top-level (field, wiretype, value) triples of one protobuf message."""
    i, out = 0, []
    while i < len(b):
        k, i = varint(b, i)
        f, w = k >> 3, k & 7
        if w == 0:
            v, i = varint(b, i)
        elif w == 2:
            n, i = varint(b, i)
            if i + n > len(b):
                raise ValueError("truncated")
            v, i = b[i:i + n], i + n
        elif w == 1:
            v, i = b[i:i + 8], i + 8
        elif w == 5:
            v, i = b[i:i + 4], i + 4
        else:
            raise ValueError("wire type %d" % w)
        out.append((f, w, v))
    return out


def ints(msg):
    return {f: v for f, w, v in fields(msg) if w == 0}


def reading(blob):
    top = fields(blob)
    usage = [v for f, w, v in top if f == 9 and w == 2]
    if not usage:
        return None
    u = ints(usage[0])
    if 2 not in u:
        raise ValueError("usage without uncached input")
    fresh, cached = u[2], u.get(5, 0)
    if fresh + cached <= 0:
        raise ValueError("usage with no input")
    return 100.0 * cached / (fresh + cached)


def main():
    if len(sys.argv) != 2 or not re.fullmatch(r"[A-Za-z0-9-]{1,64}", sys.argv[1]):
        return
    base = os.environ.get("AGY_CONVERSATIONS_DIR") or os.path.expanduser(
        "~/.gemini/antigravity-cli/conversations")
    path = os.path.join(base, sys.argv[1] + ".db")
    if not os.path.isfile(path):
        return
    # as_uri() percent-escapes the path, so a "?" or "#" in it can never end
    # the path early and drop mode=ro (which would create an empty database).
    uri = pathlib.Path(path).absolute().as_uri() + "?mode=ro"
    db = sqlite3.connect(uri, uri=True, timeout=0.5)
    try:
        rows = db.execute(
            "select metadata from steps where metadata is not null"
            " order by idx desc limit ?", (SCAN,))
        for (blob,) in rows:
            try:
                r = reading(bytes(blob))
            except (ValueError, IndexError):
                return
            if r is not None:
                print("%.4f" % r)
                return
    finally:
        db.close()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
