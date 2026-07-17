# Shader port status

Source shaders live under `PixelPlanets/Planets/`. See [porting.md](porting.md) for the
translation approach.

| Original shader | Status | Ported as |
|---|---|---|
| `BlackHole/BlackHole.gdshader` | Ported | `src/shaders/black-hole.lisp` (`:black-hole`) |
| `NoAtmosphere/NoAtmosphere.gdshader` | Ported | `src/shaders/no-atmosphere.lisp` (`:no-atmosphere`) |
| `Star/Star.gdshader` | Ported | `src/shaders/star.lisp` (`:star`) |
| `BlackHole/BlackHoleRing.gdshader` | Pending | — |
| `Star/StarBlobs.gdshader` | Pending | — |
| `Star/StarFlares.gdshader` | Pending | — |
| `NoAtmosphere/Craters.gdshader` | Pending | — |
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

"Pending" shaders are tracked under the `PLANETS` label on the tracker (multi-layer
compositing, remaining shaders, DSL re-expression, resize handling, and live GUI
controls — see the follow-up tickets filed after milestone 1).
