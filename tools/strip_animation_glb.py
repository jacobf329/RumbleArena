#!/usr/bin/env python3
"""Strip mesh, texture and material data out of an animation-only .glb.

Every clip Meshy exports carries its own copy of the character mesh and a 2K
texture -- about 6.3 MB per animation, none of which is needed once one file
supplies the model. This rewrites a clip to keep only the node hierarchy, the
skin and the animation, substituting a single degenerate skinned triangle for
the mesh so Godot still builds the same Skeleton3D and still produces bone
tracks rather than node-path tracks.

Usage: strip_animation_glb.py <in.glb> <out.glb>
"""
import json
import struct
import sys
from pathlib import Path

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
COMPONENT_FORMATS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
TYPE_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    data = Path(path).read_bytes()
    _, _, length = struct.unpack_from("<III", data, 0)
    offset, gltf, binary = 12, None, b""
    while offset < length:
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8:offset + 8 + chunk_length]
        if chunk_type == JSON_CHUNK:
            gltf = json.loads(chunk.decode("utf-8"))
        elif chunk_type == BIN_CHUNK:
            binary = chunk
        offset += 8 + chunk_length + (-chunk_length % 4)
    return gltf, binary


def accessor_bytes(gltf, binary, index):
    """Re-pack one accessor tightly, dropping any interleaving."""
    accessor = gltf["accessors"][index]
    fmt = COMPONENT_FORMATS[accessor["componentType"]]
    components = TYPE_COUNTS[accessor["type"]]
    element = struct.calcsize(fmt) * components
    view = gltf["bufferViews"][accessor["bufferView"]]
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride") or element
    out = bytearray()
    for i in range(accessor["count"]):
        out += binary[start + i * stride:start + i * stride + element]
    return bytes(out)


def strip(src, dst):
    gltf, binary = read_glb(src)

    out_buffer = bytearray()
    out_views = []
    out_accessors = []

    def add_accessor(raw, accessor_template):
        while len(out_buffer) % 4:
            out_buffer.append(0)
        view_index = len(out_views)
        out_views.append({"buffer": 0, "byteOffset": len(out_buffer), "byteLength": len(raw)})
        out_buffer.extend(raw)
        accessor = dict(accessor_template)
        accessor["bufferView"] = view_index
        accessor.pop("byteOffset", None)
        accessor.pop("sparse", None)
        out_accessors.append(accessor)
        return len(out_accessors) - 1

    remap = {}

    def keep(index):
        if index not in remap:
            remap[index] = add_accessor(
                accessor_bytes(gltf, binary, index), gltf["accessors"][index])
        return remap[index]

    for animation in gltf.get("animations", []):
        for sampler in animation["samplers"]:
            sampler["input"] = keep(sampler["input"])
            sampler["output"] = keep(sampler["output"])

    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = keep(skin["inverseBindMatrices"])

    # A single skinned triangle stands in for the mesh. The skin must still be
    # referenced by a mesh-bearing node or Godot will not build a Skeleton3D.
    joint_count = len(gltf["skins"][0]["joints"]) if gltf.get("skins") else 1
    positions = add_accessor(
        struct.pack("<9f", 0, 0, 0, 0, 0.001, 0, 0.001, 0, 0),
        {"componentType": 5126, "count": 3, "type": "VEC3",
         "min": [0, 0, 0], "max": [0.001, 0.001, 0]})
    joints = add_accessor(
        struct.pack("<12H", *([0, 0, 0, 0] * 3)),
        {"componentType": 5123, "count": 3, "type": "VEC4"})
    weights = add_accessor(
        struct.pack("<12f", *([1.0, 0.0, 0.0, 0.0] * 3)),
        {"componentType": 5126, "count": 3, "type": "VEC4"})
    indices = add_accessor(
        struct.pack("<3H", 0, 1, 2), {"componentType": 5123, "count": 3, "type": "SCALAR"})

    gltf["meshes"] = [{
        "name": "anim_stub",
        "primitives": [{
            "attributes": {"POSITION": positions, "JOINTS_0": joints, "WEIGHTS_0": weights},
            "indices": indices,
            "material": 0,
        }],
    }]
    gltf["materials"] = [{"name": "anim_stub", "pbrMetallicRoughness": {
        "baseColorFactor": [1, 1, 1, 1]}}]
    for key in ("images", "textures", "samplers"):
        gltf.pop(key, None)
    for node in gltf["nodes"]:
        if "mesh" in node:
            node["mesh"] = 0
    gltf["accessors"] = out_accessors
    gltf["bufferViews"] = out_views
    gltf["buffers"] = [{"byteLength": len(out_buffer)}]
    gltf.pop("extensionsUsed", None)
    gltf.pop("extensionsRequired", None)

    json_chunk = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    json_chunk += b" " * (-len(json_chunk) % 4)
    bin_chunk = bytes(out_buffer) + b"\x00" * (-len(out_buffer) % 4)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    with open(dst, "wb") as handle:
        handle.write(struct.pack("<III", 0x46546C67, 2, total))
        handle.write(struct.pack("<II", len(json_chunk), JSON_CHUNK))
        handle.write(json_chunk)
        handle.write(struct.pack("<II", len(bin_chunk), BIN_CHUNK))
        handle.write(bin_chunk)
    return joint_count


if __name__ == "__main__":
    joints = strip(sys.argv[1], sys.argv[2])
    before = Path(sys.argv[1]).stat().st_size
    after = Path(sys.argv[2]).stat().st_size
    print("%-26s %7.2f MB -> %6.1f KB  (%d joints)" % (
        Path(sys.argv[2]).name, before / 1e6, after / 1e3, joints))
