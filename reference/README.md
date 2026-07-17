# Reference captures

Captured from the live Godot project (`godot --path PixelPlanets Planets/<X>/<X>.tscn`) and
from `pixel-planets:render-all-planets-png`, for eyeballing the port against the original.

- `*-godot-full.png` — the **full composited Godot scene**. All overlay layers are now
  ported and composited by `render-planet-png` too (BlackHole+`BlackHoleRing.gdshader`;
  NoAtmosphere+`Craters.gdshader`; Star+`StarBlobs.gdshader`+`StarFlares.gdshader` — see
  [../docs/porting.md#multi-layer-compositing](../docs/porting.md#multi-layer-compositing)).
  Still not a pixel-for-pixel target — compare palette, light direction, composition, and
  noise character, not exact pixels.
- `*-ported.png` — headless output of the corresponding ported shader alone
  (`pixel-planets:render-planet-png`).

Random seeds differ between captures (the Godot GUI seeds itself randomly on each run), so
exact noise placement will never match between a `-godot-full` and `-ported` pair — only the
overall structure should.
