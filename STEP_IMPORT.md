# Offline STEP import

The Android model picker accepts `.step` and `.stp` in addition to STL/3MF.
CAD surfaces are tessellated locally into a binary STL in millimetres. All
meshes are combined in their imported assembly positions; colours, object
names and editable CAD features are not retained. Input limit: 20 MiB;
output: 500,000 triangles. Deflection: 0.05 mm, angular deflection: 0.25 rad.
The complete output continues through the existing mesh preview, plate,
project save, support analysis and slicing paths.

Before local Flutter builds, run:

    python3 scripts/prepare_step_importer.py

The script verifies the exact npm SHA512 of occt-import-js 0.0.23 and bundles
its unmodified Open CASCADE 7.6.1 WebAssembly module inside a worker.
No runtime download or model upload is used. A local WebView hosts the worker;
input and output cross the bridge in acknowledged chunks. Cancellation terminates
the worker. A two-minute timeout and bounded output reject excessive models.
The model parser has no access to the Android filesystem or network. The page
blocks network access through CSP and accepts only local asset navigation.
This first integration uses the existing WebView platforms; Windows needs a
separate runtime before STEP can be enabled there.

Android CI runs the preparation with `--sources`. Every release includes
`STEP-importer-source.zip`: the complete npm package with wrapper sources,
OCCT source at d2abb6d844231cb8f29be6894440874a4700e4a5, and build/replacement
instructions for Emscripten 3.1.69. Licenses are bundled in the app's license
screen. The source archive is linked in the slicer's information menu.
Generated vendor bundles and downloaded licenses are not committed.

Upstream: https://github.com/kovacsv/occt-import-js/tree/0.0.23
OCCT source: https://github.com/Open-Cascade-SAS/OCCT/tree/d2abb6d844231cb8f29be6894440874a4700e4a5
