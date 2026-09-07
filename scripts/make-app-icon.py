#!/usr/bin/env python3
"""Draw the TodoCompanion app icon and write the macOS asset catalog.

Kept in the repo so the icon can be regenerated or tweaked rather than existing
only as a set of PNGs nobody knows the origin of.

    python3 scripts/make-app-icon.py

Requires Pillow (`pip install Pillow`).
"""

from __future__ import annotations

import json
import os

from PIL import Image, ImageDraw

CANVAS = 1024
# Apple's icon grid leaves the art short of the bounds; the shadow and optical
# alignment of the dock depend on that margin existing.
MARGIN = 100
RADIUS = 185

GRADIENT_TOP = (91, 88, 245)
GRADIENT_BOTTOM = (147, 51, 234)

OUTPUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "TodoCompanion",
    "TodoCompanion",
    "Assets.xcassets",
    "AppIcon.appiconset",
)

# (size in points, scale) pairs macOS expects for an app icon.
MAC_VARIANTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    gradient = Image.new("RGB", (1, size))
    for y in range(size):
        blend = y / max(1, size - 1)
        gradient.putpixel(
            (0, y),
            tuple(round(top[channel] + (bottom[channel] - top[channel]) * blend) for channel in range(3)),
        )
    return gradient.resize((size, size))


def rounded_mask(size: int, margin: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, size - margin, size - margin], radius=radius, fill=255
    )
    return mask


def draw_viewfinder(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], arm: int, thickness: int) -> None:
    """Four corner brackets — the app reads the screen, so it looks like a frame."""
    left, top, right, bottom = box
    white = (255, 255, 255, 235)
    half = thickness // 2

    for x_edge, x_dir in ((left, 1), (right, -1)):
        for y_edge, y_dir in ((top, 1), (bottom, -1)):
            draw.line(
                [(x_edge, y_edge), (x_edge + arm * x_dir, y_edge)], fill=white, width=thickness
            )
            draw.line(
                [(x_edge, y_edge), (x_edge, y_edge + arm * y_dir)], fill=white, width=thickness
            )
            # Square off the elbow so the two strokes meet cleanly.
            draw.ellipse(
                [x_edge - half, y_edge - half, x_edge + half, y_edge + half], fill=white
            )


def draw_bookmark(draw: ImageDraw.ImageDraw, center_x: int, top: int, width: int, height: int) -> None:
    """The saved-context mark: this app keeps things on purpose."""
    half = width // 2
    notch = int(height * 0.26)
    draw.polygon(
        [
            (center_x - half, top),
            (center_x + half, top),
            (center_x + half, top + height),
            (center_x, top + height - notch),
            (center_x - half, top + height),
        ],
        fill=(255, 255, 255, 255),
    )


def render_master() -> Image.Image:
    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))

    plate = vertical_gradient(CANVAS, GRADIENT_TOP, GRADIENT_BOTTOM).convert("RGBA")
    icon.paste(plate, (0, 0), rounded_mask(CANVAS, MARGIN, RADIUS))

    overlay = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)

    inset = MARGIN + 108
    draw_viewfinder(
        draw,
        box=(inset, inset, CANVAS - inset, CANVAS - inset),
        arm=118,
        thickness=34,
    )
    draw_bookmark(draw, center_x=CANVAS // 2, top=394, width=176, height=250)

    return Image.alpha_composite(icon, overlay)


def main() -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    master = render_master()

    pixel_sizes = sorted({points * scale for points, scale in MAC_VARIANTS})
    for pixels in pixel_sizes:
        master.resize((pixels, pixels), Image.LANCZOS).save(
            os.path.join(OUTPUT_DIR, f"{pixels}-mac.png")
        )

    contents = {
        "images": [
            {
                "filename": f"{points * scale}-mac.png",
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{points}x{points}",
            }
            for points, scale in MAC_VARIANTS
        ],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(OUTPUT_DIR, "Contents.json"), "w") as handle:
        json.dump(contents, handle, indent=2)
        handle.write("\n")

    print(f"Wrote {len(pixel_sizes)} PNGs and Contents.json to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
