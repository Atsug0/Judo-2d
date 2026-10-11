"""Lecture / écriture minimale de fichiers glTF binaires (.glb) avec numpy."""
import json
import struct

import numpy as np

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    b = open(path, "rb").read()
    _, _, _ = struct.unpack("<4sII", b[:12])
    off = 12
    js = None
    bin_ = b""
    while off < len(b):
        ln, typ = struct.unpack("<II", b[off:off + 8])
        chunk = b[off + 8:off + 8 + ln]
        if typ == 0x4E4F534A:
            js = json.loads(chunk)
        else:
            bin_ = chunk
        off += 8 + ln
    return js, bin_


def accessor(js, bin_, idx):
    a = js["accessors"][idx]
    bv = js["bufferViews"][a["bufferView"]]
    dt = COMP[a["componentType"]]
    n = NCOMP[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    count = a["count"]
    if stride and stride != n * np.dtype(dt).itemsize:
        raw = np.frombuffer(bin_, dtype=np.uint8, count=stride * count, offset=start).reshape(count, stride)
        arr = raw[:, :n * np.dtype(dt).itemsize].copy().view(dt).reshape(count, n)
    else:
        arr = np.frombuffer(bin_, dtype=dt, count=count * n, offset=start).reshape(count, n)
    return arr if n > 1 else arr[:, 0]


def image_bytes(js, bin_, idx):
    im = js["images"][idx]
    bv = js["bufferViews"][im["bufferView"]]
    s = bv.get("byteOffset", 0)
    return bin_[s:s + bv["byteLength"]], im.get("mimeType", "image/png")


class Builder:
    """Assemble un .glb : tampons, vues, accesseurs."""

    def __init__(self):
        self.js = {"asset": {"version": "2.0", "generator": "judo-2d tools/rig"}, "buffers": [], "bufferViews": [],
                   "accessors": []}
        self.bin = bytearray()

    def _view(self, data: bytes, target=None):
        while len(self.bin) % 4:
            self.bin += b"\0"
        v = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target:
            v["target"] = target
        self.bin += data
        self.js["bufferViews"].append(v)
        return len(self.js["bufferViews"]) - 1

    def add(self, arr, typ, comp, target=None, minmax=False):
        arr = np.ascontiguousarray(arr)
        view = self._view(arr.tobytes(), target)
        a = {"bufferView": view, "componentType": comp, "count": int(arr.shape[0]), "type": typ}
        if minmax:
            a["min"] = [float(x) for x in arr.min(axis=0)]
            a["max"] = [float(x) for x in arr.max(axis=0)]
        self.js["accessors"].append(a)
        return len(self.js["accessors"]) - 1

    def add_image(self, data: bytes, mime: str):
        view = self._view(data)
        self.js.setdefault("images", []).append({"bufferView": view, "mimeType": mime})
        return len(self.js["images"]) - 1

    def save(self, path):
        while len(self.bin) % 4:
            self.bin += b"\0"
        self.js["buffers"] = [{"byteLength": len(self.bin)}]
        j = json.dumps(self.js, separators=(",", ":")).encode()
        while len(j) % 4:
            j += b" "
        total = 12 + 8 + len(j) + 8 + len(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total))
            f.write(struct.pack("<II", len(j), 0x4E4F534A) + j)
            f.write(struct.pack("<II", len(self.bin), 0x004E4942) + bytes(self.bin))
