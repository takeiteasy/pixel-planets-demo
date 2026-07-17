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
| `Galaxy/Galaxy.gdshader` | Pending | — |
| `GasPlanet/GasPlanet.gdshader` | Pending | — |
| `GasPlanetLayers/GasLayers.gdshader` | Pending | — |
| `GasPlanetLayers/Ring.gdshader` | Pending | — |
| `Asteroids/Asteroids.gdshader` | Pending | — |
| `LandMasses/PlanetUnder.gdshader` | Pending | — |
| `LandMasses/PlanetLandmass.gdshader` | Pending | — |
| `LandMasses/Clouds.gdshader` | Pending | — |
| `Rivers/LandRivers.gdshader` | Pending | — |
| `LavaWorld/Rivers.gdshader` | Pending | — |

"Pending" shaders are tracked under the `PLANETS` label on the tracker. Multi-layer
compositing infrastructure (draw a planet's layers back-to-front in one render pass; see
[porting.md](porting.md#multi-layer-compositing)) landed with the `no-atmosphere` planet's
`ground` + `craters` layers as the proof (same-size, identity `layer_scale`). BlackHoleRing
and StarBlobs/StarFlares followed as the oversized-quad case: the `black-hole` and `star`
planets each now composite an oversized layer (BlackHoleRing's 300px disk; StarBlobs/
StarFlares' 200px blobs/corona) around their original body, with the body's `layer_scale`
shrunk to match (see [porting.md](porting.md#multi-layer-compositing)). Still pending: two
new multi-layer planet types — LandMasses (`PlanetUnder`+`PlanetLandmass`+`Clouds`) and
GasPlanetLayers (`GasLayers`+`Ring`) — neither of which has a base layer ported yet.
Remaining single-layer shaders, DSL re-expression, resize handling, and live GUI controls
are also tracked there.
