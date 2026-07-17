# Shader port status

Source shaders live under `PixelPlanets/Planets/`. See [porting.md](porting.md) for the
translation approach.

| Original shader | Status | Ported as |
|---|---|---|
| `BlackHole/BlackHole.gdshader` | Ported | `src/shaders/black-hole.lisp` (`:black-hole`, layer `:black-hole`) |
| `NoAtmosphere/NoAtmosphere.gdshader` | Ported | `src/shaders/no-atmosphere.lisp` (`:no-atmosphere`, layer `:ground`) |
| `NoAtmosphere/Craters.gdshader` | Ported | `src/shaders/craters.lisp` (`:no-atmosphere`, layer `:craters`) |
| `Star/Star.gdshader` | Ported | `src/shaders/star.lisp` (`:star`, layer `:star`) |
| `BlackHole/BlackHoleRing.gdshader` | Ported | `src/shaders/black-hole-ring.lisp` (`:black-hole`, layer `:black-hole-ring`) |
| `Star/StarBlobs.gdshader` | Ported | `src/shaders/star-blobs.lisp` (`:star`, layer `:star-blobs`) |
| `Star/StarFlares.gdshader` | Ported | `src/shaders/star-flares.lisp` (`:star`, layer `:star-flares`) |
| `Galaxy/Galaxy.gdshader` | Ported | `src/shaders/galaxy.lisp` (`:galaxy`, layer `:galaxy`) |
| `GasPlanet/GasPlanet.gdshader` | Ported | `src/shaders/gas-planet.lisp` (`:gas-planet`, layers `:cloud`, `:cloud2`) |
| `GasPlanetLayers/GasLayers.gdshader` | Ported | `src/shaders/gas-layers.lisp` (`:gas-planet-layers`, layer `:gas-layers`) |
| `GasPlanetLayers/Ring.gdshader` | Ported | `src/shaders/ring.lisp` (`:gas-planet-layers`, layer `:ring`) |
| `Asteroids/Asteroids.gdshader` | Ported | `src/shaders/asteroids.lisp` (`:asteroids`, layer `:asteroid`) |
| `LandMasses/PlanetUnder.gdshader` | Ported | `src/shaders/planet-under.lisp` (`:land-masses`, layer `:water`) |
| `LandMasses/PlanetLandmass.gdshader` | Ported | `src/shaders/planet-landmass.lisp` (`:land-masses`, layer `:land`) |
| `LandMasses/Clouds.gdshader` | Ported | `src/shaders/clouds.lisp` (`:land-masses`, layer `:clouds`) |
| `Rivers/LandRivers.gdshader` | Pending | — |
| `LavaWorld/Rivers.gdshader` | Ported | `src/shaders/lava-rivers.lisp` (`:lava-world`, layer `:lava-rivers`) |

"Pending" shaders are tracked under the `PLANETS` label on the tracker. Multi-layer
compositing infrastructure (draw a planet's layers back-to-front in one render pass; see
[porting.md](porting.md#multi-layer-compositing)) landed with the `no-atmosphere` planet's
`ground` + `craters` layers as the proof (same-size, identity `layer_scale`). BlackHoleRing
and StarBlobs/StarFlares followed as the oversized-quad case: the `black-hole` and `star`
planets each now composite an oversized layer (BlackHoleRing's 300px disk; StarBlobs/
StarFlares' 200px blobs/corona) around their original body, with the body's `layer_scale`
shrunk to match (see [porting.md](porting.md#multi-layer-compositing)). LandMasses and
GasPlanetLayers followed as the first two planets ported with *no* prior single-layer base:
`land-masses` stacks three same-size (100px), identity-`layer_scale` layers (`water` +
`land` + `clouds`), the first case where two of the three layers are themselves partially
transparent overlays rather than an opaque base with one transparent overlay on top;
`gas-planet-layers` is the second worked oversized-layer example after BlackHoleRing (`ring`
on a 300px quad, `gas-layers` body shrunk to `layer_scale` 100/300, ring occlusion behind
the planet via `scale_rel_to_planet`). Remaining single-layer shaders, DSL re-expression,
resize handling, and live GUI controls are also tracked on the tracker.

`gas-planet` is the first of this last batch: functionally near-identical to
`LandMasses/Clouds.gdshader` (src/shaders/clouds.lisp) -- same untiled-hash RAND, same
turbulence -- but the .tscn stacks two ColorRects of this one shader with different
parameters (`:cloud` + `:cloud2` layers), and its fragment skips one alpha re-attenuation
step Clouds has (preserved as ported, not a bug).

`asteroids` and `galaxy` are new porting cases (see
[porting.md](porting.md#new-porting-cases) for detail): neither has a `spherify`-then-disc-
cutout body -- Asteroids keeps an irregular noise-derived silhouette instead of a circle,
Galaxy has no cutout at all (a full-rect swirl, alpha from dithering). Both also use an
untiled RAND (no `size`-based wrap), ported once as `phash_flat`/`fbm_flat` in
`src/shaders/common.lisp` and shared between them.

`lava-world` is the first planet to reuse already-ported layer shaders
(`no-atmosphere`/`craters`, src/shaders/no-atmosphere.lisp, src/shaders/craters.lisp) under
a *different* scene's parameters, alongside one new layer (`lava-rivers`, a lava-glow river
overlay -- not the same shader as `Rivers/LandRivers.gdshader` despite the shared filename).
LavaWorld.tscn sets its own light/palette/size values for the `ground`/`craters` layers, so
they get their own `*lava-world-ground-defaults*`/`*lava-world-craters-defaults*` rather
than sharing `*no-atmosphere-defaults*`/`*craters-defaults*` (see
[porting.md](porting.md#new-porting-cases)).
