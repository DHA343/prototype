# Orb impact experiment

Open `preview.tscn` and run the current scene (F6). The production main scene and enemy deformation remain unchanged.

- 1: Improved spark
- 2: Soft elliptical ring
- 3: Spark + ring
- 4: Toggle 0.25x slow motion
- 5: Ring + matching distortion
- 6: Distortion only
- 7: Droplets (no additional body deformation)
- 0: Off / baseline

Mouse movement, boost and brake use the existing game controls.

Tune particles and wave lifetime/radius/stretch on the Impact node in `impact.tscn`.
Tune ring color/opacity and maximum distortion on the root of `preview.tscn`.

The preview observes the existing sweep signal. Its origin is the circular enemy
hurtbox surface, including lethal hits. Particle travel and wave elongation follow
orb velocity; damage and knockback retain their existing behavior.

Ring and distortion share the same ellipse and 0.13-second envelope. Impact speed
continuously scales radius, elongation, initial expansion speed and small forward
drift, without extending lifetime. A single screen capture/pass combines up to 16
active waves; total displacement is capped at 2.5 logical viewport pixels by default.
Oldest active waves are retained if the cap is reached. The pass is disabled when
no waves remain. It runs before world post-processing and damage numbers. The
current fixed camera is supported; nonuniform camera scaling is outside this trial.

Sparks have two prominent streaks, bright cores, short width retention and varied
lifetimes. Droplets share the directional travel approach but decelerate and round
out, with a smaller backward droplet and restrained highlights. They are a visual
approximation, not a fluid simulation; their color is configured independently.

Validation: CLI script parsing; runtime mode switching and repeated real collisions;
visual inspection of particle/wave onset and fade, and combined/standalone distortion.
Performance across different hardware has not been benchmarked.
