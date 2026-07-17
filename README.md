# pixel-planets-demo

A Common Lisp + WebGPU port of [Deep-Fold's PixelPlanets](https://github.com/Deep-Fold/PixelPlanets)
(Godot 4.2, MIT) — procedurally generated pixel-art planets — built on
[cl-webgpu](https://github.com/takeiteasy/cl-webgpu).

Three planets are ported so far: black hole, airless rocky planet (no atmosphere), and a
plasma star. See [docs/shaders.md](docs/shaders.md) for full port status and
[docs/porting.md](docs/porting.md) for the GLSL → WGSL translation approach.

## Setup

This project depends on the sibling [`cl-webgpu`](../cl-webgpu) checkout. Symlink both
into Quicklisp's `local-projects`:

```sh
ln -s /path/to/cl-webgpu ~/quicklisp/local-projects/cl-webgpu
ln -s /path/to/pixel-planets ~/quicklisp/local-projects/pixel-planets
```

Build cl-webgpu's native dependencies once (see its own README):

```sh
cd cl-webgpu/deps/wgpu-native && cargo build --release
cd cl-webgpu && make
```

## Running

```sh
sbcl --load examples/view-planet.lisp
```

or from a REPL:

```lisp
(ql:quickload :pixel-planets)
(pixel-planets:run :black-hole)   ; or :no-atmosphere, :star
```

## Headless / reference-image comparison

```lisp
(ql:quickload :pixel-planets/headless)
(pixel-planets:render-all-planets-png)
```

Renders every ported planet to PNG with no window, for comparing against
`reference/*.png` captures of the Godot originals.

## License

MIT — see [LICENSE](LICENSE). Original shaders and design copyright (c) 2020 Deep-Fold.
