# Jelly Ascent Hero
## Development Session Summary

**Date:** October 1, 2026  
**Project basis:** `jelly_ascent_hero.md`  
**Engine:** Godot 4.7.2  

This report summarizes the game systems implemented and refined during the session. It reflects the current implementation, not every temporary iteration. Some files were undone during the session and later rebuilt; user edits to the level scene were preserved.

## Project Direction

The GDD remains the source of truth: Jelly Ascent is a physics-based vertical climber built around momentum, wall ricochets, deformable platforms, increasingly challenging tower layouts, biomes, and a rising acid hazard.

The starter project was expanded into a playable prototype with movement, platform variants, procedural ascent, biomes, a menu-to-run loop, and local score storage.

## Player Movement and Wall Bounces

- Replaced basic constant-speed movement with horizontal acceleration, momentum carry, braking, and a speed cap.
- Added a fast-drop control and biome-adjusted gravity.
- Manual jumps require a fresh Space/Enter press on a catch platform; Super-Trampoline and Slingshot Ramp launch on contact.
- Wall bounces require more than **600 px/s** of impact speed. Qualifying impacts gain a stronger upward impulse and retain horizontal speed.
- Added a short post-bounce momentum grace so opposing input or drag does not immediately cancel a wall launch. At sufficient speed, the player can travel from one side of the 700 px arena to the other.
- The player remains a `CharacterBody2D`, keeping movement and collision behavior in the existing controller.

## Platform System

- Integrated the installed appsinacup SoftBody2D addon.
- SoftBody2D is used for Super-Trampoline and Slingshot Ramp. Standard and Fragile platforms use a frozen `RigidBody2D`.
- Standard platform widths are randomized in **32 px increments** across the configured range; collision widths match their repeated atlas tiles.
- Platform thickness was reduced to **12 px** for the rigid platform and softbody texture without changing horizontal lengths.
- Platforms allow upward pass-through until approximately **90% of the player’s body** has cleared the platform surface; collision is then restored.
- Standard and Fragile platforms catch the player and require manual jump input. Powered trampoline and slingshot types launch automatically.
- Standard and Fragile platform visuals use repeating 32 px atlas tiles, with collision widths snapped to the same grid.

## Procedural Tower and Hazards

- Added chunk-based platform generation with ladder, zig-zag, slingshot-gap, fragile-sprint, and standard patterns.
- Vertical gaps and horizontal shifts increase with altitude.
- The opening route uses standard platforms. Powered-platform probability increases gradually with altitude, with a minimum standard-platform streak between specials.
- Some Standard platforms spawn near and physically attached to the left or right wall. Their randomized width range remains unchanged.
- A full-width Standard platform is added when entering each new biome.
- Added an accelerating rising acid floor, player collision detection, and a game-over state.

## Biomes

Biome transitions occur every **500 m**, using the project’s 10 px-per-meter scale:

- **Standard Tower:** baseline physics.
- **Gale-Force Winds:** periodic lateral forces while airborne.
- **Frosted Peaks:** reduced horizontal drag for longer momentum carry.
- **Crushing Abyss:** 3.5× gravity with launch compensation.

Biome transitions also update platform-generation weighting, apply a visual tint, show a temporary banner, and add a full-width platform.

## Camera and Art Preparation

- The world and viewport are **700 px wide**.
- The camera is fixed horizontally at the world center and follows the player vertically only.
- Jump-reactive zoom and camera smoothing were removed to eliminate camera jitter.
- Side-wall visuals use 64 × 128 seamless tiles, mixed from the platform assets with four variants for each biome; wall collision is unchanged.
- Slingshot ramps spawn at the left or right world edge and launch inward according to their facing.

## Menus, HUD, and Progression

- Set the Main Menu as the project entry scene, with Start, Tutorial, Leaderboard, and Quit actions.
- Replaced the debug HUD with altitude in meters, score, and combo.
- Added pause/resume, retry, and return-to-menu actions.
- Added game-over scoring and a local top-10 leaderboard stored at `user://leaderboard.save`.
- Score is calculated from altitude and combo.
- A project-wide pixel font and dark text outline now cover labels, buttons, HUD readouts, and text entry.

## Verification

- Repeated Godot 4.7.2 headless startup checks on Level 1 completed successfully, including 10–30 frame smoke checks during development.
- Editor diagnostics reported no errors for the final touched scripts/scenes at their respective validation points.
- Visible Level 1 builds were launched for hands-on testing.
- Interactive balance, wall-to-wall play, biome transitions at 500 m, pause/resume, and the full game-over/leaderboard flow still need deliberate manual playtesting. Smoke tests confirm startup and parsing; they do not prove those longer gameplay paths feel correct.

## Remaining Work

- Tune movement, wall-to-wall ricochet, and powered-platform spacing through real playtests.
- Exercise each biome transition and full-width biome platform at its altitude threshold.
- Test pause, retry, game-over, and leaderboard saving end to end.
- Replace remaining placeholder acid art and add audio, transition polish, and the remaining Phase 6 presentation/balance work from the GDD.
- Add audio, transition polish, and the remaining Phase 6 presentation/balance work from the GDD.

## Key Files

- `jelly_ascent_hero.md` — game design source of truth.
- `Scenes/player.gd` and `Scenes/player.tscn` — movement, wall bounce, player visuals, and vertical camera tracking.
- `Scenes/platform.gd` and `Scenes/platform.tscn` — platform types, rigid/softbody setup, bounce, and pass-through behavior.
- `Scenes/level_controller.gd` and `Scenes/Level_1.tscn` — procedural tower, hazards, biomes, and run flow.
- `Scenes/MainMenu.tscn` and `Scenes/main_menu.gd` — menu and tutorial/leaderboard views.
- `Scenes/local_leaderboard.gd` — local score persistence.
