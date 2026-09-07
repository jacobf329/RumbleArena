#!/usr/bin/env python3
"""No script may need an imported asset in order to finish parsing.

A `preload` resolves while the script is being parsed. If what it reaches is an
asset Godot has to import first -- a .glb, a texture -- then on a first launch,
before anything has been imported, the parser is racing the importer. Lose that
race and the script fails to compile, its `class_name` never reaches the global
class cache, and every script referencing it goes down too. Autoloads included:
the arena renders perfectly and nothing responds to the controller.

That failure has now shipped twice and been re-invented a third time, by
`const DEFAULT_VISUAL := preload("...ninja.tres")` -- a plain resource whose own
ExtResource was a .glb. The chain is what makes it easy to miss, so this follows
the chain.

`preload` of a .tscn is deliberately not followed. Scene preloads have been in
this project since the first milestone and have never failed a cold start, so
treating them as hazards would be a rule invented from theory that fires on
working code. If a cold start ever does fail on one, widen this.

    python3 tools/check_preloads.py [project-dir]      exit 1 if anything is unsafe
"""
import re
import sys
from pathlib import Path

# Extensions Godot imports before they can be loaded.
IMPORTED = {".glb", ".gltf", ".obj", ".fbx", ".dae", ".blend",
            ".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tga", ".svg",
            ".ogg", ".wav", ".mp3", ".ttf", ".otf"}
# Resources that are plain data but may reference imported assets in turn.
FOLLOWED = {".tres", ".res"}

PRELOAD = re.compile(r'preload\(\s*"(res://[^"]+)"')
EXT_RESOURCE = re.compile(r'path\s*=\s*"(res://[^"]+)"')


def resolve(root: Path, res_path: str) -> Path:
    return root / res_path[len("res://"):]


def chase(root: Path, res_path: str, trail: list, seen: set) -> list | None:
    """The trail from a preload to an imported asset, or None if it never gets
    to one."""
    if res_path in seen:
        return None
    seen.add(res_path)
    suffix = Path(res_path).suffix.lower()
    if suffix in IMPORTED:
        return trail + [res_path]
    if suffix not in FOLLOWED:
        return None
    target = resolve(root, res_path)
    if not target.is_file():
        return None
    for reference in EXT_RESOURCE.findall(target.read_text(errors="replace")):
        found = chase(root, reference, trail + [res_path], seen)
        if found:
            return found
    return None


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    problems = []
    for script in sorted(root.rglob("*.gd")):
        if ".godot" in script.parts:
            continue
        for line_number, line in enumerate(
                script.read_text(errors="replace").splitlines(), 1):
            for target in PRELOAD.findall(line):
                trail = chase(root, target, [], set())
                if trail:
                    problems.append((script.relative_to(root), line_number, trail))

    if not problems:
        print("Preloads: no script needs an imported asset to parse.")
        return 0

    print("FAILED: a script preloads its way to an asset Godot has to import.")
    print("On a first launch the parser races the importer for it; losing that")
    print("race takes the script, its class_name, and every autoload with it.")
    print("Load it at runtime instead -- see FighterVisual.default_visual().")
    for path, line_number, trail in problems:
        print("\n  %s:%d" % (path, line_number))
        print("    " + "\n      -> ".join(trail))
    return 1


if __name__ == "__main__":
    sys.exit(main())
