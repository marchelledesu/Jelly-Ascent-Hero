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
| - Windy Biome (501m - 1000m)   -> Dynamic gust forces                 |
| - Frosted Peaks (1001m - 1500m)-> Low friction & high slippage        |
| - Crushing Abyss (1501m+)      -> Heavy gravity scale modifier        |
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

* **Momentum Storage:** Sustained movement input linearly builds lateral momentum toward a maximum speed cap (`max_horizontal_speed = 900.0`).
* **Wall Bounce Ricochet:** Colliding with side walls while maintaining horizontal speed converts lateral energy into an upward diagonal launch vector. Higher impact speed produces greater rebound elevation.
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
| **Slingshot Ramp** | Blue | Angled surface with dynamic rotation. Converts impact into high-speed diagonal launches toward walls. |
| **Fragile Tile** | Red | Low breaking threshold. Snaps and collapses shortly after initial player contact. |
| **Sticky Dough** | Yellow | High physical damping. Absorbs all velocity, safely catching players while resetting combos. |
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
2. **Dynamic Gap Scaling:** As the player climbs higher, the minimum and maximum vertical distances between platform spawns scale upward (`min_gap = 120.0` to `max_gap = 280.0`), demanding higher rebound velocities.
3. **Procedural Biome Weighting:** Platform generation probabilities adapt to the current active biome:
   * **Standard Biome:** Balanced distribution of all platform types.
   * **Windy Biome:** Higher spawn rate of *Slingshot Ramps* to encourage wide diagonal launches.
   * **Frosted Peaks:** Increased *Fragile Tiles* and wider gaps.
   * **Crushing Abyss:** Higher frequency of *Super-Trampolines* to offset heavy gravity pull.

---

### 2.6 Biomes & Environmental Modifiers

The tower shifts environmental biomes every 500 meters of elevation:

| Biome Tier | Altitude Range | Active Modifier | Visual/Environmental Effect |
| :--- | :--- | :--- | :--- |
| **Standard Tower** | 0m – 500m | Default Physics | Standard gravity scale and baseline friction values. |
| **Gale-Force Winds** | 501m – 1000m | Dynamic Wind Vectors | Periodic lateral wind forces push the player mid-air. |
| **Frosted Peaks** | 1001m – 1500m | Ultra-Low Friction | Reduced surface friction; stored momentum persists longer. |
| **Crushing Abyss** | 1501m+ | Heavy Gravity (`3.5x`) | Heavy downward pull requiring high-velocity rebounds. |

---

### 2.7 Environmental Hazards

* **Rising Acid Floor:** Rises continuously from the bottom of the viewport with steady acceleration. Touching the acid floor triggers an immediate Game Over.

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
* **Leaderboard Screen:** Stores and displays top historical scores locally (`user://leaderboard.save`), complete with rank, score, and altitude achieved.
* **Game Over Screen:** Displays final height achieved, current combo performance, automatic score submission to the leaderboard, and options to Retry or return to the Main Menu.

---

## 4. Game Feel, Visuals & Technical Polish

* **Dynamic Camera Zoom:** Camera smoothly zooms out during high-speed vertical ascents to offer a broader view of upcoming procedural platform formations.
* **Audio Pitch Shift:** Collision and squish SFX pitch-shift dynamically based on impact velocity and softbody deformation depth.
* **Visual Biome Alerts:** Transitioning into new biomes triggers an animated banner notification detailing active weather modifiers.