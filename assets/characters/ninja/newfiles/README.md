# Armored ninja — Godot asset pack

Open `project.godot` in Godot 4 and press F6 on `preview.tscn` (or F5). Tested with Godot 4.7.2. Select a move, replay it, change playback speed, orbit with right-drag, and zoom with the wheel.

## Use in your game

Copy `assets/`, `ninja_actor.gd`, `ninja_actor.tscn`, and `headband_wind.gdshader` together into your project. The supplied resource paths expect these at the project root; if placing them in a subfolder, update the `res://` paths in both scripts and scenes. Instance `ninja_actor.tscn` under your player controller. Call `play_move("backflip")` or another animation name. The actor is a visual component, not a CharacterBody3D controller.

`assets/ninja.glb` contains the textured, skinned ninja and all 15 named custom animations in one AnimationPlayer. `assets/headband_tails.glb` contains the separate textured tails, normalized to 45 cm with their attachment end at the origin. The actor attaches them to the Head bone and supplies wind deformation. Both assets have 2048 x 2048 textures. The character is approximately 1.75 m tall and about 20,757 triangles.

## Custom animations

backflip, front_flip, jump, crouch, pickup, throw, punch_jab, punch_cross, kick_front, kick_side, somersault_forward, somersault_backward, roundhouse, crane_kick, ninja_run.

All were generated from individual written prompts with Meshy Text to Motion Prime, then applied to the same character using Meshy's motion_task_id support. No preset action IDs were used. The run is made stationary in X/Z in the assembled GLB and loops in the actor. Other actions preserve generated travel relative to their starting point; the preview camera follows the hips. Your controller should extract or handle root motion to prevent double movement. The raw Meshy files are retained outside this Godot project in the parent delivery folder.

## Integration limits

- This is a first animation pass, with engine import and sampled visual checks, not a finished combat controller. Tune timing, blending, hitboxes, contact events, and landing alignment for your game.
- The automatic rig has hand bones but no individual finger bones. Punch and pickup animations do not articulate fingers into a fist or grip.
- Pickup and throw are body motions. Attach your item to the right hand at the pickup event and detach/spawn its physics motion at the throw release event. Event timing must match your item and gameplay.
- The headband is animated with a vertex wind shader. It follows the head but does not collide with armor or simulate physical cloth. Wind strength and speed are shader parameters.
- Armor is skinned with the body, so extreme poses can bend plates or intersect. No separate rigid armor rig, facial rig, LOD chain, or collision mesh is included.
- The run was requested as a loop and configured to loop, but further seam polishing may be useful for your preferred movement speed.

## API and credits

Task-reported costs: two design images 18, two textured meshes 60, character rig 5, fifteen Prime motions 150, fifteen applications 45: total **278 credits**.

The account balance changed from 2,005 at the initial connection check to 1,447 after generation: a 558-credit difference. This exceeds the sum of this pack's task records by 280 credits. The detailed Usage API returned HTTP 403 because it requires Studio or Enterprise; the discrepancy is unresolved. No additional paid requests were submitted after detecting it. See `generation_manifest.json` for task IDs and reported costs.

The local Text to Motion bridge successfully used the existing Meshy API key. No API key, credential, or signed download URL is included in this package.

References: https://docs.meshy.ai/en/api/text-to-motion and https://docs.meshy.ai/en/api/animation
