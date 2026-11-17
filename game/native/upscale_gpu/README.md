# Vulkan art preparation on Windows

Build the optional x64 backend with Visual Studio 2022 and the
[ncnn 20261020 static Windows SDK](https://github.com/Tencent/ncnn/releases/tag/20261020)
(`ncnn-20261020-windows-vs2022.zip`).

```powershell
cmake -S game/native/upscale_gpu -B build/upscale_gpu -A x64 -DCMAKE_PREFIX_PATH=C:/path/to/ncnn-20261020-windows-vs2022/x64
cmake --build build/upscale_gpu --config Release
Copy-Item build/upscale_gpu/Release/el_upscale_gpu.dll game/native/bin/
```

The backend uses the Microsoft Visual C++ x64 runtime and a Vulkan driver.
The game loads it from beside the native asset library when preparation starts.
If loading or inference fails, preparation uses the existing CPU implementation.
