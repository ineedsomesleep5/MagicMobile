#!/usr/bin/env python3
"""Resize the textures embedded in a .glb without touching anything else (scripts/brand, art pipeline cleanup).

    python3 scripts/brand/glb_textures.py IN.glb OUT.glb --max 1024

Each embedded image (PNG or JPEG) is resized with macOS `sips` so its longer side is at most --max pixels, keeping its
aspect ratio and format; buffer views are repacked (4-byte aligned) and the JSON's byteLengths updated. Meshes,
materials, accessors and node names are byte-for-byte the same, so the apps' loaders (SceneKit on iOS, Filament on
Android) and the face data in d20.json see the same model. Prints a JSON summary.
"""
import argparse, json, os, struct, subprocess, sys, tempfile


def read_glb(path):
    data = open(path, "rb").read()
    magic, version, length = struct.unpack("<III", data[:12])
    assert magic == 0x46546C67 and version == 2, "not a glTF 2 binary"
    offset, chunks = 12, {}
    while offset < length:
        size, kind = struct.unpack("<II", data[offset:offset + 8])
        chunks[kind] = data[offset + 8:offset + 8 + size]
        offset += 8 + size
    return json.loads(chunks[0x4E4F534A]), chunks.get(0x004E4942, b"")


def write_glb(path, doc, binary):
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    total = 12 + 8 + len(text) + 8 + len(binary)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A) + text)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def resize(image_bytes, mime, longest):
    suffix = ".png" if mime == "image/png" else ".jpg"
    with tempfile.TemporaryDirectory() as tmp:
        src, out = os.path.join(tmp, "in" + suffix), os.path.join(tmp, "out" + suffix)
        open(src, "wb").write(image_bytes)
        info = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", src], capture_output=True, text=True).stdout.split()
        w, h = int(info[info.index("pixelWidth:") + 1]), int(info[info.index("pixelHeight:") + 1])
        if max(w, h) <= longest:
            return image_bytes, (w, h), (w, h)
        args = ["sips", "-Z", str(longest), src, "--out", out]
        if mime == "image/jpeg":
            args[1:1] = ["-s", "formatOptions", "90"]
        subprocess.run(args, check=True, capture_output=True)
        info = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", out], capture_output=True, text=True).stdout.split()
        return open(out, "rb").read(), (w, h), (int(info[info.index("pixelWidth:") + 1]), int(info[info.index("pixelHeight:") + 1]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("src"); parser.add_argument("dst"); parser.add_argument("--max", type=int, default=1024)
    a = parser.parse_args()
    doc, binary = read_glb(a.src)
    image_views = {img["bufferView"]: img for img in doc.get("images", []) if "bufferView" in img}
    pieces, report = [], []
    for index, view in enumerate(doc["bufferViews"]):
        chunk = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
        if index in image_views:
            image = image_views[index]
            new, before, after = resize(chunk, image.get("mimeType", "image/png"), a.max)
            report.append({"image": image.get("name", index), "from": before, "to": after, "bytes": [len(chunk), len(new)]})
            chunk = new
        pieces.append((index, chunk))
    out, offset = bytearray(), 0
    for index, chunk in pieces:
        pad = -len(out) % 4
        out += b"\0" * pad
        doc["bufferViews"][index]["byteOffset"] = len(out)
        doc["bufferViews"][index]["byteLength"] = len(chunk)
        out += chunk
    doc["buffers"][0]["byteLength"] = len(out)
    write_glb(a.dst, doc, bytes(out))
    print(json.dumps({"src": a.src, "dst": a.dst, "bytes": [os.path.getsize(a.src), os.path.getsize(a.dst)], "images": report}))


if __name__ == "__main__":
    sys.exit(main())
