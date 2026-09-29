# Orb impact experiment

Open `preview.tscn` and run the current scene (F6). The project main scene is unchanged.

- 1: Spark
- 2: Ring
- 3: Both
- 0: Effects off (baseline)
- 4: Toggle 0.25x slow motion
- Mouse movement, boost and brake use the existing game controls.

Edit the Impact node in `impact.tscn` to tune colors, particle count, travel distance,
line length/width, ring radius/width and lifetimes in the Inspector.

This scene instances the existing main scene and observes its sweep-hit signal.
Only this preview creates effects. No production scene, script, resource or input
mapping is modified. Effects use the current circular enemy hurtbox surface as
their origin, including lethal hits; this adapter assumes the existing circle shape.
Damage numbers retain their original enemy-center origin. Effects fade at their
world-space impact position, independently of the enemy's lifetime.

The spark lasts 0.18 seconds and the ring 0.20 seconds. Impact speed scales their
size/travel, with restrained variation in spark directions. Existing post-processing
is retained. The HUD is drawn above it for readable comparison controls.
