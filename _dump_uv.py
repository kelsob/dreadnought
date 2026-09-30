import json
import math
import struct

path = r"C:\Users\kelso\Documents\deadnot\assets\glbs\Cockpit.glb"
with open(path, "rb") as f:
    magic, version, length = struct.unpack("<4sII", f.read(12))
    json_chunk = None
    bin_chunk = None
    while f.tell() < length:
        clen, ctype = struct.unpack("<I4s", f.read(8))
        data = f.read(clen)
        if ctype.startswith(b"JSON"):
            json_chunk = json.loads(data)
        elif ctype.startswith(b"BIN"):
            bin_chunk = data

gltf = json_chunk
bin_data = bin_chunk
nodes = gltf["nodes"]
meshes = gltf["meshes"]
accessors = gltf["accessors"]
views = gltf["bufferViews"]
component_sizes = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
type_counts = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(idx):
    acc = accessors[idx]
    view = views[acc["bufferView"]]
    offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    count = acc["count"]
    n = type_counts[acc["type"]]
    size = component_sizes[acc["componentType"]]
    stride = view.get("byteStride", n * size)
    fmt = {5126: "f", 5123: "H", 5125: "I", 5121: "B"}[acc["componentType"]]
    out = []
    for i in range(count):
        start = offset + i * stride
        vals = struct.unpack_from("<" + fmt * n, bin_data, start)
        out.append(vals if n > 1 else vals[0])
    return acc, out


def quat_to_euler_deg(q):
    x, y, z, w = q
    # glTF xyzw
    sinr = 2 * (w * x + y * z)
    cosr = 1 - 2 * (x * x + y * y)
    roll = math.degrees(math.atan2(sinr, cosr))
    sinp = 2 * (w * y - z * x)
    sinp = max(-1.0, min(1.0, sinp))
    pitch = math.degrees(math.asin(sinp))
    siny = 2 * (w * z + x * y)
    cosy = 1 - 2 * (y * y + z * z)
    yaw = math.degrees(math.atan2(siny, cosy))
    return roll, pitch, yaw


want = ("RadarFace", "RadarFace-col", "RadarDome", "RadarPanel", "RadarScreen")
for i, node in enumerate(nodes):
    name = node.get("name", "")
    if not any(k in name for k in ("Radar", "radar")):
        continue
    print("==== NODE", i, name)
    for key in ("translation", "rotation", "scale", "matrix"):
        if key in node:
            print(" ", key, node[key])
            if key == "rotation":
                print("  euler deg (roll,pitch,yaw)", quat_to_euler_deg(node[key]))
    if "mesh" in node:
        mesh = meshes[node["mesh"]]
        print("  mesh", node["mesh"], mesh.get("name"))
        prim = mesh["primitives"][0]
        attrs = prim["attributes"]
        pos_acc, positions = read_accessor(attrs["POSITION"])
        uv_acc, uvs = read_accessor(attrs["TEXCOORD_0"])
        print("  pos count", len(positions), "min", pos_acc.get("min"), "max", pos_acc.get("max"))
        # UV principal axes: find vertex with max Y (local) and its UV
        # For a disc in XZ, "12 o'clock" might be +Z or -Z
        xs = [p[0] for p in positions]
        ys = [p[1] for p in positions]
        zs = [p[2] for p in positions]
        print("  x", min(xs), max(xs), "y", min(ys), max(ys), "z", min(zs), max(zs))
        # vertex farthest in +Z (and +X) and their UVs
        i_z = max(range(len(positions)), key=lambda i: positions[i][2])
        i_x = max(range(len(positions)), key=lambda i: positions[i][0])
        i_y = max(range(len(positions)), key=lambda i: positions[i][1])
        print("  max +X vert", positions[i_x], "uv", uvs[i_x])
        print("  max +Y vert", positions[i_y], "uv", uvs[i_y])
        print("  max +Z vert", positions[i_z], "uv", uvs[i_z])
        # angle of UV from center vs position from center in XZ
        cx = (min(xs) + max(xs)) / 2
        cz = (min(zs) + max(zs)) / 2
        uc = (min(u[0] for u in uvs) + max(u[0] for u in uvs)) / 2
        vc = (min(u[1] for u in uvs) + max(u[1] for u in uvs)) / 2
        angles = []
        for p, uv in zip(positions, uvs):
            ax = math.atan2(p[2] - cz, p[0] - cx)
            au = math.atan2(uv[1] - vc, uv[0] - uc)
            d = math.degrees(au - ax)
            while d > 180:
                d -= 360
            while d < -180:
                d += 360
            angles.append(d)
        angles.sort()
        mid = angles[len(angles) // 2]
        print("  UV vs XZ angle deg: median", round(mid, 3), "min", round(angles[0], 3), "max", round(angles[-1], 3), "span", round(angles[-1] - angles[0], 3))
        print("  uv u", min(u[0] for u in uvs), max(u[0] for u in uvs), "v", min(u[1] for u in uvs), max(u[1] for u in uvs))
