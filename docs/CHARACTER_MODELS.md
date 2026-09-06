# Character models and animation packs

A character's body is data: a `CharacterVisual` resource holding a model, an
animation library, and how to recolour it. A ninja wears one by pointing its
`.tres` at one. Nothing in `fighter.gd` knows which model it is driving.

```
src/characters/character_visual.gd     the resource
src/characters/visuals/ninja.tres      the default body
assets/characters/<pack>/              model .glb, texture, clips/, library .res
```

---

## Are the animations tied to the model?

**No.** They are skeleton bone tracks, not baked mesh data. Every clip in
`ninja_animations.res` addresses bones by name:

```
Armature/Skeleton3D:Hips
Armature/Skeleton3D:LeftUpLeg
Armature/Skeleton3D:RightForeArm
...
```

That means a clip plays on **any** model whose skeleton uses the same bone names
in the same rest orientation, and carries no dependency on the mesh, the
texture, or the proportions of the character it was exported from. This is on
purpose: `tools/strip_animation_glb.py` throws away the mesh from every clip
export and leaves a single degenerate skinned triangle behind, specifically so
Godot still builds a `Skeleton3D` and still produces **bone** tracks rather than
node-path tracks. That is the whole reason the ten clips cost 350 KB instead of
63 MB.

The current pack's skeleton is 24 bones, Mixamo-style naming:

```
Hips  Spine  Spine01  Spine02  neck  Head  head_end  headfront
LeftShoulder  LeftArm  LeftForeArm  LeftHand
RightShoulder RightArm RightForeArm RightHand
LeftUpLeg  LeftLeg  LeftFoot  LeftToeBase
RightUpLeg RightLeg RightFoot RightToeBase
```

**Matching is by name, and a mismatch is silent.** There used to be an eleventh
clip, `rigify_clip`, exported from a Rigify rig: its tracks addressed
`target_character/Skeleton3D:<bone>` against Rigify's naming. Godot resolved
zero of its 22 tracks, so it had never animated anything — it just printed
twenty `couldn't resolve track` warnings every time a fighter spawned. It is
excluded from the library build now (`SKIP` in
`tools/build_animation_library.gd`); the `.glb` stays on disk because it is
still a usable source once retargeted.

So, in practice:

| The new pack's skeleton | What you do |
|---|---|
| Same bone names (both Mixamo-derived, most likely) | Nothing. Either pack's clips play on either model. Share one library between them. |
| Different names, same structure | Retarget once — import both in Blender, copy the action onto the target rig, re-export. Or rename bones on import. |
| Genuinely different skeleton (extra joints, different rest pose) | Retarget in Blender. There is no runtime fix. |

The safe check is one line: if the two models' skeletons list the same bone
names, the animations are interchangeable.

---

## What a pack has to supply

1. **A model `.glb`** — one skinned mesh, one albedo texture. The recolour
   shader rotates the hue of the texture's saturated source colour, so the pack
   declares which hue that is (`source_hue`). A texture whose character colour
   is near-grey cannot be recoloured this way; near-grey pixels have a
   meaningless hue that explodes when it is rotated.
2. **Clips named what the movesets name.** The moveset asks for
   `roundhouse_kick`; whatever library the character brought must contain a clip
   called that. Rename the `.glb` files before the library build rather than
   adding a runtime remap — a moveset is shared between characters and must not
   learn one of their vocabularies.

Clips the game currently asks for:

```
walk  run                                     locomotion
punch_combo  double_kick  roundhouse_kick      strikes
shoulder_throw                                grab
spin_jump                                     air heavy / slam
run_alt  run_fast                             spares
```

A pack missing a clip is not fatal — the move plays no animation and everything
else about it still works.

---

## Adding one

```bash
# 1. Drop the raw exports in place
assets/characters/<pack>/<pack>_model.glb
assets/characters/<pack>/animations/<clip>.glb      # one animation per file

# 2. Strip the mesh out of every clip (6.3 MB -> ~35 KB each)
python3 tools/strip_animation_glb.py raw/<clip>.glb assets/characters/<pack>/animations/<clip>.glb

# 3. Build the library
godot --headless --path . --script res://tools/build_animation_library.gd

# 4. Author the body
src/characters/visuals/<pack>.tres        # model, animations, scale, mesh_node, source_hue

# 5. Point one ninja at it
src/characters/roster/<name>.tres         # visual = ExtResource("<pack>.tres")
```

Step 3 currently builds one hard-coded pack; point `CLIP_DIR` and `OUTPUT` at
the new one, or pass them, when there is a second.

`model_scale` puts the model's height onto the 1.8 m collision capsule — the
current model stands 1.69 m, hence 1.065. `faces_positive_z` is true for a model
authored with its toes pointing +Z, which the game turns to meet Godot's -Z
forward. Get either wrong and it is obvious the first time you look at it, which
is why `tools/capture_screenshots.tscn` exists.
