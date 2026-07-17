# Shader port status

Source shaders live under `PixelPlanets/Planets/`. See [porting.md](porting.md) for the
translation approach.

| Original shader | Status | Ported as |
|---|---|---|
| `BlackHole/BlackHole.gdshader` | Ported | `src/shaders/black-hole.lisp` (`:black-hole`, layer `:black-hole`) |
| `NoAtmosphere/NoAtmosphere.gdshader` | Ported | `src/shaders/no-atmosphere.lisp` (`:no-atmosphere`, layer `:ground`) |
| `NoAtmosphere/Craters.gdshader` | Ported | `src/shaders/craters.lisp` (`:no-atmosphere`, layer `:craters`) |
| `Star/Star.gdshader` | Ported | `src/shaders/star.lisp` (`:star`, layer `:star`) |
| `BlackHole/BlackHoleRing.gdshader` | Pending | — |
| `Star/StarBlobs.gdshader` | Pending | — |
| `Star/StarFlares.gdshader` | Pending | — |
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
`ground` + `craters` layers as the proof. Still pending as follow-ups on the same
infrastructure: BlackHoleRing and StarBlobs/StarFlares as additional layers on the existing
`black-hole`/`star` planets (these exercise the oversized-quad `layer_scale` path, unlike
`craters` which is same-size as `ground`), and two new multi-layer planet types —
LandMasses (`PlanetUnder`+`PlanetLandmass`+`Clouds`) and GasPlanetLayers
(`GasLayers`+`Ring`) — neither of which has a base layer ported yet. Remaining
single-layer shaders, DSL re-expression, resize handling, and live GUI controls are also
tracked there.
