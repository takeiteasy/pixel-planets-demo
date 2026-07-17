# pixel-planets-demo

A Common Lisp + WebGPU port of [Deep-Fold's PixelPlanets](https://github.com/Deep-Fold/PixelPlanets)
(Godot 4.2, MIT) — procedurally generated pixel-art planets — built on
[cl-webgpu](https://github.com/takeiteasy/cl-webgpu). Doubles as a visual prototyping demo
for the `star` game project, which is why the two share a tracker (see CLAUDE.md).

Every planet from the original project is ported — black holes, rocky/airless worlds,
gas giants, a star, a galaxy, asteroid fields, land masses, rivers, lava worlds, ice
worlds, and dry terrans. See [docs/shaders.md](docs/shaders.md) for the full list and port
status and [docs/porting.md](docs/porting.md) for the GLSL → WGSL translation approach.
The window has a live Nuklear GUI for tuning any planet's parameters and switching planets
— see [docs/gui.md](docs/gui.md).

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
(pixel-planets:run :black-hole)   ; see src/planets.lisp for the full list of names
```

The window is resizable and includes a live GUI panel — drag any layer's sliders/
colour-pickers, or switch planets from the combo box at the top. See
[docs/gui.md](docs/gui.md).

## Headless PNG capture

```lisp
(ql:quickload :pixel-planets/headless)
(pixel-planets:render-all-planets-png)
```

Renders every ported planet to PNG with no window or display server (see
`src/headless.lisp`) — useful for regression screenshots or CI.

## License

MIT — see [LICENSE](LICENSE). Original shaders and design copyright (c) 2020 Deep-Fold.
