# Reference captures

Captured from the live Godot project (`godot --path PixelPlanets Planets/<X>/<X>.tscn`) and
from `pixel-planets:render-all-planets-png`, for eyeballing the port against the original.

- `*-godot-full.png` — the **full composited Godot scene**, including overlay layers not yet
  ported (BlackHole also renders `BlackHoleRing.gdshader`; NoAtmosphere also renders
  `Craters.gdshader`; Star also renders `StarBlobs.gdshader` + `StarFlares.gdshader`). These
  are not a pixel-for-pixel target for the currently-ported base shaders — compare palette,
  light direction, and noise character, not exact pixels, until the overlay layers are ported
  (see the multi-layer-compositing follow-up ticket).
- `*-ported.png` — headless output of the corresponding ported shader alone
  (`pixel-planets:render-planet-png`).

Random seeds differ between captures (the Godot GUI seeds itself randomly on each run), so
exact noise placement will never match between a `-godot-full` and `-ported` pair — only the
overall structure should.
