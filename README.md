# Quinta3d

## The World Worst 3D Engine!!!

![PicturesA](https://github.com/Calaverd/Quinta3d/tree/master/assets/quinta_3d.png?raw=true)

Quinta 3d is a very bare bones 3d render engine build on top of LOVE2D **more like a demo that something to be used seriously.** 

Based on parts of [*Groverburger's Super Simple 3D Engine*](https://github.com/groverburger/ss3d)
Using [CPML](https://github.com/excessive/cpml) for the math on the CPU side, and leaving the GPU for rendering.

At the moment the engine lacks a proper scene culling, so should be avoided to render "big" scenes.
The only file formats accepted for the engine are *obj* and [*iqm*](https://github.com/lsalzman/iqm).

I spec the **main.lua** file to be self explanatory. 

## TODO

- [ ] Phong lighting.
- [ ] Support for mtl files. 
- [ ] Add proper culling.
- [ ] Well, make it *suck* less.
