# GAME DESIGN DOCUMENT: JELLY ASCENT V2 (EXPANDED EDITION)

## 1. Executive Overview

* **Project Title:** Jelly Ascent (working title)
* **Course / Module:** GD373
* **Author / Designer:** Marchelle Escoña
* **Target Engine & Plugins:** Godot Engine 4.x | SoftBody2D by appsinacup
* **Genre:** Physics-Based Arcade Vertical Climber
* **High Concept:** An *Icy Tower*-inspired endless climber where a physics-driven, squishy protagonist ascends a dangerous, procedurally generated, ever-rising tower populated with bouncy softbody platform power-tiles, wall-bounce momentum mechanics, and shifting weather biomes.
* **Core Loop:** Bounce on softbody tiles → Build & store lateral momentum → Ricochet off walls or launch upward → Navigate procedurally generated platform chunks and weather biomes → Escape accelerating acid floor → Climb high to register on the leaderboard.

---

## 2. Gameplay Mechanics & Physics Engine

### 2.1 Complete Core Gameplay Loop

```
+-----------------------------------------------------------------------+
|                    1. LAUNCH & MOMENTUM BUILDING                      |
| Executing rebounds off SoftBody2D platforms or building horizontal    |
| speed using sustained left/right input vectors.                      |
+-----------------------------------------------------------------------+
                                   |
                                   v
+-----------------------------------------------------------------------+
|                 2. AIRBORNE TRAVERSAL & WALL BOUNCES                  |
| Adjust trajectory in mid-air or ricochet off side walls, converting  |
| horizontal speed into high-elevation diagonal launches.               |
+-----------------------------------------------------------------------+
                                   |
                                   v
+-----------------------------------------------------------------------+
|               3. PROCEDURAL PLATFORM SELECTION                        |
| Navigate dynamically generated platform formations & power-tiles:     |
| - Super-Trampoline (Green) -> Maximum upward momentum & combo boost   |
| - Slingshot Ramp (Blue)    -> High-speed diagonal launch w/ angle     |
| - Fragile Tile (Red)       -> Quick escape jump before tile collapses |
| - Sticky Dough (Yellow)    -> Emergency brake & momentum absorption   |
| - Standard Tile (Gray)     -> Base elastic platform rebound           |
+-----------------------------------------------------------------------+
                                   |
                                   v
+-----------------------------------------------------------------------+
|             4. ENVIRONMENTAL CONDITIONS & BIOMES                      |
| Adapt to environmental shifts and modifiers every 500 meters:         |
| - Standard Biome (0m - 500m)    -> Balanced gravity & friction        |
| - Windy Biome (501m - 1000m)   -> Powerful shifting crosswinds        |
| - Frosted Peaks (1001m - 1500m)-> Slippery steering & wider gaps      |
| - Crushing Abyss (1501m+)      -> 2.0x gravity & wider platform gaps   |
+-----------------------------------------------------------------------+
                                   |
                                   v
+-----------------------------------------------------------------------+
|                 5. HAZARD ESCAPE & PROGRESSION                        |
| Stay ahead of the accelerating Acid Floor to survive, score high      |
| combo points, and register runs on the leaderboard.                   |
+-----------------------------------------------------------------------+
```

* **Micro Loop (Second-to-Second):** Accelerate horizontal momentum → Time wall bounces or softbody landings → React to procedural platform layouts → Compensate for active environmental conditions.
* **Macro Loop (Run-to-Run):** Start run → Traverse changing procedural biomes → Build high combo multipliers → Set new height high score on the leaderboard → Re-enter run with improved physics control.

---

### 2.2 Player Physics, Locomotion & Wall Rebounds (`RigidBody2D`)

* **Momentum Storage:** Sustained movement input gradually builds lateral momentum toward the current 700 px/s speed cap. Airborne steering is deliberately controlled rather than overly strong, while counter-steering still reduces carried speed faster to help aim platform landings. Biome conditions modify handling: Frosted Peaks lowers steering acceleration to 55% and passive drag to 8%, while crosswinds push airborne players with gusts up to 880 px/s².
* **Speed-Based Jumps:** Manual jumps gain up to 35% more upward speed based on the player's horizontal running speed immediately before takeoff, including jumps entered on a platform-landing frame.
* **Wall Bounce Ricochet:** Colliding with side walls while maintaining horizontal speed converts impact into an upward rebound while retaining only 25% of horizontal speed, discouraging wall-to-wall bouncing. A wall bounce cannot trigger again until the player lands on a platform. The impact is stored as a bonus to the next platform jump, scaling with impact speed. Pressing toward the bounce direction within 120 ms before or after impact earns an immediate horizontal momentum boost and a larger stored jump bonus. Side walls follow the player vertically so they remain present throughout the ascent.
* **Platform Pass-Through:** Platforms only collide with the player when the player is descending onto their top surface; upward movement and side approaches pass through to prevent snagging.
* **Jump-Chain Scoring:** Consecutive manual jumps, automatic platform launches, and qualifying wall bounces build the combo count used for score bonuses. Each unique platform passed upward without landing adds one combo point on the next landing; the jump itself adds its normal point, so skipping three platforms adds four points total. The platform actually landed on does not count as skipped. Landing on the same platform twice in a row breaks the combo; the landing can start a new combo chain. Special platforms that already award a combo only count once per launch.
* **Timed Combo and Stored Jump Bonus:** The combo resets after 3 seconds without another combo event. A stored wall-bounce jump bonus expires after 4 seconds if unused. A compact HUD panel shows both timers and reserves sprite slots for future icons.
* **Platform Grip:** Platforms use higher-friction physics materials, and landing reduces carried horizontal speed to help prevent sliding off.
* **Super-Trampoline:** Provides a substantially stronger upward launch than standard platforms as the most rewarding vertical boost.
* **Downward Fast Drop:** Downward directional input increases gravity scale (`gravity_scale = 4.0`), allowing players to execute sharp drops onto softbody platforms for maximum compression and launch height.
* **Dynamic Recoil:** Downward impact velocity onto softbody platforms converts directly into upward launch impulses modified by platform elasticity.

---

### 2.3 Player Control Scheme

| Input Action | Keyboard / Mouse | Gamepad | Touch (Mobile) | Physics Implementation |
| :--- | :--- | :--- | :--- | :--- |
| **Move Left** | A / Left Arrow | D-Pad Left / Left Stick | Touch Left Zone | Applies leftward central force vector; builds momentum. |
| **Move Right** | D / Right Arrow | D-Pad Right / Left Stick | Touch Right Zone | Applies rightward central force vector; builds momentum. |
| **Fast Drop** | S / Down Arrow | D-Pad Down / Left Stick | Swipe Down | Scales gravity up to force dynamic softbody compression. |
| **Pause** | Esc / P | Start / Menu | On-Screen Pause | Sets `Engine.time_scale = 0` and overlays Pause UI. |

---

### 2.4 Platform Types & Properties

| Platform Type | Base Color | Mechanical Properties & SoftBody Behaviors |
| :--- | :--- | :--- |
| **Super-Trampoline** | Green | High elasticity, low stiffness. Flings player skyward and increments combo multiplier. |
| **Slingshot Ramp** | Blue | Angled surface spawns at either side of the tower and faces inward for a high-speed diagonal launch. |
| **Fragile Tile** | Red | One-use platform. Remains available while the player stands on it, then disables collision and collapses shortly after the player jumps away. |
| **Sticky Dough** | Yellow | Reusable, non-collapsing platform. High physical damping absorbs most horizontal momentum and resets combos. Its jump uses the standard platform's normal jump speed, but horizontal acceleration is reduced while standing on it. A standard platform is generated next at regular vertical spacing and within reachable horizontal range to keep the route progressing. |
| **Standard Rigid** | Gray | Basic platform with default elastic rebound properties. |

---

### 2.5 Procedural Level Generation System

```
                  [ UNSPAWNED TOWER SPACE ]
                              |
                              v  (Triggers when Player Y approaches threshold)
       +---------------------------------------------+
       |         CHUNK PATTERN SELECTION             |
       |  - Weighted selection based on altitude     |
       |  - Standard, Ladder, Zig-Zag, Slingshot Gap |
       +---------------------------------------------+
                              |
                              v
       +---------------------------------------------+
       |         BIOME VARIATION & GAP SCALING       |
       |  - Vertical gaps scale: 120px -> 280px      |
       |  - Apply platform type weights per biome    |
       |  - Add random rotation to Slingshot Ramps   |
       +---------------------------------------------+
                              |
                              v
                  [ INSTANTIATE IN SCENE ]
```

1. **Chunk-Based Pattern Generation:** Platforms spawn in pre-configured structural "chunks" (e.g., *Zig-Zag Wall Bounce*, *Trampoline Ladder*, *Fragile Sprint*, *Slingshot Gap*) mixed with weighted random variations to ensure every ascent feels unique.
2. **Dynamic Gap Scaling:** As the player climbs higher, the minimum and maximum vertical distances between platform spawns scale upward, demanding higher rebound velocities. Platforms within 60 px of an exact biome transition platform are removed to prevent overlap.
3. **Procedural Biome Weighting:** Platform generation probabilities adapt to the current active biome. Blue Slingshot Ramps spawn only along the left or right side and mirror their slope to launch inward:
   * **Standard Biome:** Balanced distribution of all platform types.
   * **Windy Biome:** Higher spawn rate of *Slingshot Ramps* to encourage wide diagonal launches.
   * **Frosted Peaks:** Increased *Fragile Tiles* and wider gaps.
   * **Crushing Abyss:** Higher frequency of *Super-Trampolines* to offset heavy gravity pull.
   * **Higher Altitudes:** Special platforms appear more often, standard-only streaks shorten, and up to 25% of special-platform selections are additionally weighted toward *Super-Trampolines* or *Slingshot Ramps*.

---

### 2.6 Biomes & Environmental Modifiers

The tower shifts environmental biomes every 500 meters of elevation. A full-width standard platform is placed at the exact 500 m, 1000 m, and 1500 m boundaries, measured from the player's starting altitude:

| Biome Tier | Altitude Range | Active Modifier | Visual/Environmental Effect |
| :--- | :--- | :--- | :--- |
| **Standard Tower** | 0m – 500m | Default Physics | Standard gravity scale and baseline friction values. |
| **Gale-Force Winds** | 501m – 1000m | Strong shifting wind gusts | Mid-air crosswinds can reach 880 px/s² acceleration. Animated wind streaks and a storm-blue tint reinforce the lateral pushes. |
| **Frosted Peaks** | 1001m – 1500m | Low grip (`0.08x` drag, `0.55x` steering) | Momentum persists and steering/braking respond more slowly, with platform gaps increased by 10–15 px. Falling snow and an icy tint mark the zone. |
| **Crushing Abyss** | 1501m+ | Heavy Gravity (`2.0x`) | Stronger downward pull, while preserving enough airtime to steer and wall-bounce; gaps increased by 18–24 px keep traversal demanding. Dark violet shading and rising motes signal the danger. |

---

### 2.7 Environmental Hazards

* **Score Scale:** Score is `10 points per best meter + 5 points per best combo point`, keeping a 1,000 m run near 10,000 points instead of immediately reaching six digits.
* **Rising Acid Floor:** The acid begins below the player and rises continuously, accelerating gradually over time. Touching the acid ends the run. Final altitude and combo score use the run's best height and combo.

---

## 3. UI, Leaderboards & Progression Systems

```
+------------------+     +------------------+     +-------------------+
|    Main Menu     | --> | Interactive Level| --> |    Gameplay HUD   |
| (Start/Tut/Exit) |     |    (Tutorial)    |     | (Height/Combo/    |
+------------------+     +------------------+     |  Biome Banner)    |
         |                                        +-------------------+
         v                                                  |
+------------------+                                        v
|   Leaderboard    | <---------------------------------+    |
|   (Top Scores)   |                                   |    |
+------------------+                                   |    v
         ^                                        +-------------------+
         |--------------------------------------- |  Game Over Screen |
                                                  | (Final Score/     |
                                                  | Leaderboard/Retry)|
                                                  +-------------------+
```

### 3.1 Interface & Screen Breakdown

* **In-Game HUD:** Features real-time height meter, active combo multiplier display, dynamic Biome Banner announcements upon entering new zones, and pause menu controls.
* **Leaderboard Screen:** Stores and displays top historical scores locally (`user://leaderboard.save`), complete with player name, rank, score, and altitude achieved.
* **Game Over Screen:** Displays final height achieved and best combo performance. Players enter a name before their score is saved to the leaderboard, then can Retry or return to the Main Menu.
* **Developer Test Panel:** During gameplay, type `/dev` and press Enter to open a panel for spawning every platform type, forcing any biome, testing jump/wall-bounce/combo/stored-bonus behavior, and opening the end-run score-entry flow.
* **Gameplay Tuning:** Balance values are centralized in [`Scenes/game_tuning.gd`](./Scenes/game_tuning.gd), grouped by world/generation, biome conditions, player movement, platform physics, and scoring. Gameplay scripts reference this file so edits there are the source of truth.

---

## 4. Game Feel, Visuals & Technical Polish

* **Dynamic Camera Zoom:** Camera smoothly zooms out during high-speed vertical ascents to offer a broader view of upcoming procedural platform formations.
* **Audio Pitch Shift:** Collision and squish SFX pitch-shift dynamically based on impact velocity and softbody deformation depth.
* **Visual Biome Alerts:** Transitioning into new biomes triggers an animated banner notification detailing active weather modifiers.