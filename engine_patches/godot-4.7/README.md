# Godot 4.7 engine patches (Windows Vulkan template)

Patches for the Windows x86_64 export templates that add NVIDIA Streamline
(DLSS, DLAA, Ray Reconstruction, DLSS Frame Generation, Reflex) and AMD
FidelityFX (FSR 3.1 / FSR 4 upscaling and frame generation) to the Forward+
renderer on Vulkan. Other platforms use the stock templates.

- Base: Godot `4.7-stable`, commit `5b4e0cb0fd279832bbdd69fed5354d4e5ad26f88`.
- Apply in file-name order (`git apply` or `git am`):
  1. `0001` graphics SDK seam header (`drivers/vulkan/graphics_sdk_vulkan.h`)
  2. `0002` seam wiring in the Vulkan context and device drivers
  3. `0003` Streamline owner (`drivers/streamline`, `use_streamline`, startup owner reader)
  4. `0004` `SCALING_3D_MODE_DLSS`, `Viewport.frame_generation`, ray reconstruction inputs
  5. `0005` background temporal scene shader preparation
  6. `0006` DLSS effect
  7. `0007` `SCALING_3D_MODE_FSR_SDK` availability hook
  8. `0008` requested owner in the seam
  9. `0009` shared owner value, provider feature chain
  10. `0010` FidelityFX (`drivers/fsr_sdk`, FSR effect, `use_fsr_sdk`)
  11. `0011` worker tasks nobody waited for release their callables before
      the script languages exit (stock 4.7 crashes at exit otherwise)
- SDK headers are not part of the series. `tools/engine/prepare_streamline_sdk.py`
  and `tools/engine/prepare_fsr_sdk.py` install them (and stage the signed
  runtime DLLs and licences) from the pinned, hash-checked SDK releases.

Build flags (MinGW cross-build):

```
platform=windows arch=x86_64 target=template_release production=yes
optimize=speed lto=none debug_symbols=no use_mingw=yes use_static_cpp=yes
d3d12=no vulkan=yes use_streamline=yes use_fsr_sdk=yes
module_mono_enabled=no module_openxr_enabled=no accesskit=no
```

`tools/engine/build_windows_template.sh WORK_DIR OUTPUT_DIR` does all of the
above for `template_release` and `template_debug`.

The graphics SDK that owns presentation is read at startup from
`user://graphics_sdk.cfg` (`[startup] owner = "nvidia"`, `"amd"` or `""`);
`--graphics-sdk=<owner>` overrides it. Streamline starts only for `nvidia`,
FidelityFX frame generation only for `amd`; FSR upscaling works with any owner.
