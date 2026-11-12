"""Boot splash variants for Windows builds with the graphics SDKs.

The ordinary splash (game/assets/branding/splash.png) stays as it is; these
copies add the vendors' unmodified logos, scaled with their proportions kept,
in a row under the title:

  splash-graphics.png  NVIDIA GeForce RTX + AMD FSR Upscaling + AMD FSR Frame Generation
  splash-nvidia.png    NVIDIA GeForce RTX
  splash-fsr.png       AMD FSR Upscaling + AMD FSR Frame Generation

  python tools/generate_sdk_splash.py

An SDK build's export uses one of them through the project setting
application/boot_splash/image (the "graphics_sdk" feature override in
project.godot uses splash-graphics.png).
"""
import hashlib
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BRANDING = ROOT / "game" / "assets" / "branding"
VENDORS = BRANDING / "vendors"
# The badge inside the NVIDIA file (the rest is its plain page).
NVIDIA_BADGE = (290, 278, 290 + 2420, 278 + 730)
ROW_TOP = 885
ROW_HEIGHT = 96
CELL_WIDTH = 230
GAP = 36

VARIANTS = {
    "splash-graphics.png": ["nvidia-geforce-rtx-white.png", "amd-fsr-upscaling-white.png", "amd-fsr-frame-generation-white.png"],
    "splash-nvidia.png": ["nvidia-geforce-rtx-white.png"],
    "splash-fsr.png": ["amd-fsr-upscaling-white.png", "amd-fsr-frame-generation-white.png"],
}


def logo(name: str) -> Image.Image:
    image = Image.open(VENDORS / name).convert("RGBA")
    if name.startswith("nvidia"):
        image = image.crop(NVIDIA_BADGE)
    image.thumbnail((CELL_WIDTH, ROW_HEIGHT), Image.Resampling.LANCZOS)
    return image


def variant(names: list[str]) -> Image.Image:
    splash = Image.open(BRANDING / "splash.png").convert("RGBA")
    row_width = len(names) * CELL_WIDTH + (len(names) - 1) * GAP
    left = (splash.width - row_width) // 2
    for i, name in enumerate(names):
        image = logo(name)
        x = left + i * (CELL_WIDTH + GAP) + (CELL_WIDTH - image.width) // 2
        y = ROW_TOP + (ROW_HEIGHT - image.height) // 2
        splash.alpha_composite(image, (x, y))
    return splash.convert("RGB")


def main() -> None:
    for output, names in VARIANTS.items():
        path = BRANDING / output
        variant(names).save(path, optimize=True)
        print(output, hashlib.sha256(path.read_bytes()).hexdigest())


if __name__ == "__main__":
    main()
