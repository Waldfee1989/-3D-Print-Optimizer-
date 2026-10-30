# Local slicing component

The Android package executes CuraEngine as a separate command-line program. It
exchanges STL, JSON and G-code files; the engine is not linked into the Flutter
or model-geometry library. No top-level license for this repository is changed.

- CuraEngine 4.13.1: `ebb53015413c568ccf20c050ef0d68c3072da9f9`, AGPLv3-or-later.
- stb: `d5d052c806eee2ca1f858cb58b2f062d9fa25b90`, MIT alternative selected.
- Cura default definitions: `97d20bff1b1a2cc2c13f11ec35997c2fa2f61063`, LGPLv3.
- Bundled Clipper and RapidJSON retain their upstream notices.

`build_slicer_engine.py` applies Android build adaptations, an explicitly sized
path buffer, fixed-width integer declarations and parent-death termination on
Android. Published `CuraEngine-source.zip` includes those exact modified source
trees, dependencies, build scripts, original definition resources, license texts,
source revision information and the app source from that release. Its
`REPRODUCE.txt` explains rebuilding. The same notices are available in the app's
license view. The source download is reachable from the slicer information menu.

The initial runtime profile targets Kobra S1 with a 0.4 mm nozzle. Its `G9111`
startup comes from the official ANYCUBIC-3D/AnycubicSlicerNext machine definition:
`resources/profiles/Anycubic/machine/Anycubic Kobra S1 0.4 nozzle.json`.
The app does not transmit files, move a printer or start heaters. Physical print
quality, fit and material calibration still require a test print.
