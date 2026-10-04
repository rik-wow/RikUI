"""Lossless, bounded storage for private build evidence. No geometry is published."""
import gzip
import io


def encode(raw, cap):
    if not 0 < len(raw) <= cap:
        raise ValueError("Geometry decoded byte bound")
    return gzip.compress(raw, compresslevel=3, mtime=0)


def decode(stored, cap):
    if not 0 < len(stored) <= cap:
        raise ValueError("Geometry stored byte bound")
    with gzip.GzipFile(fileobj=io.BytesIO(stored), mode="rb") as stream:
        raw = stream.read(cap + 1)
    if not 0 < len(raw) <= cap:
        raise ValueError("Geometry decoded byte bound")
    return raw
