from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable, Sequence

import numpy as np
from PIL import Image, ImageDraw


BACKGROUND_HEX = "#F8F6F1"
INK_GREEN_HEX = "#485C50"
FOREGROUND_CANVAS = 1024
FOREGROUND_HEIGHT = 410

# The source artwork is 1254 x 1254. These two closed cubic paths follow the
# outside glass contour of the supplied botanical "i" without tracing its
# internal plant detail.
DOT_PATH: Sequence[tuple[str, tuple[float, ...]]] = (
    ("M", (624, 240)),
    ("C", (585, 237, 558, 269, 559, 322)),
    ("C", (559, 371, 582, 405, 625, 407)),
    ("C", (668, 409, 692, 382, 693, 336)),
    ("C", (695, 286, 668, 244, 624, 240)),
    ("Z", ()),
)

STEM_PATH: Sequence[tuple[str, tuple[float, ...]]] = (
    ("M", (626, 448)),
    ("C", (568, 448, 528, 481, 525, 540)),
    ("C", (522, 594, 544, 638, 547, 685)),
    ("C", (550, 740, 522, 799, 527, 896)),
    ("C", (530, 978, 568, 1024, 622, 1025)),
    ("C", (681, 1026, 716, 989, 715, 915)),
    ("C", (714, 839, 691, 788, 700, 711)),
    ("C", (708, 646, 721, 594, 718, 541)),
    ("C", (715, 483, 680, 448, 626, 448)),
    ("Z", ()),
)


def _hex_rgb(value: str) -> tuple[int, int, int]:
    return tuple(int(value[index : index + 2], 16) for index in (1, 3, 5))


def _cubic_points(
    start: tuple[float, float],
    control1: tuple[float, float],
    control2: tuple[float, float],
    end: tuple[float, float],
    steps: int = 48,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    p0 = np.asarray(start, dtype=float)
    p1 = np.asarray(control1, dtype=float)
    p2 = np.asarray(control2, dtype=float)
    p3 = np.asarray(end, dtype=float)
    for index in range(1, steps + 1):
        t = index / steps
        point = (
            ((1 - t) ** 3) * p0
            + 3 * ((1 - t) ** 2) * t * p1
            + 3 * (1 - t) * (t**2) * p2
            + (t**3) * p3
        )
        points.append((float(point[0]), float(point[1])))
    return points


def _flatten_path(
    commands: Sequence[tuple[str, tuple[float, ...]]],
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    current = (0.0, 0.0)
    for command, values in commands:
        if command == "M":
            current = (values[0], values[1])
            points.append(current)
        elif command == "C":
            control1 = (values[0], values[1])
            control2 = (values[2], values[3])
            end = (values[4], values[5])
            points.extend(_cubic_points(current, control1, control2, end))
            current = end
        elif command != "Z":
            raise ValueError(f"Unsupported path command: {command}")
    return points


def _draw_source_mask(size: tuple[int, int], supersample: int = 4) -> Image.Image:
    large = Image.new("L", (size[0] * supersample, size[1] * supersample), 0)
    draw = ImageDraw.Draw(large)
    for commands in (DOT_PATH, STEM_PATH):
        polygon = [
            (round(x * supersample), round(y * supersample))
            for x, y in _flatten_path(commands)
        ]
        draw.polygon(polygon, fill=255)
    return large.resize(size, Image.Resampling.LANCZOS)


def _centered_scaled_mark(source: Image.Image, alpha: Image.Image) -> Image.Image:
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("The logo mask is empty")
    rgba = source.convert("RGBA")
    rgba.putalpha(alpha)
    cropped = rgba.crop(bbox)
    scale = FOREGROUND_HEIGHT / cropped.height
    width = max(1, round(cropped.width * scale))
    resized = cropped.resize((width, FOREGROUND_HEIGHT), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (FOREGROUND_CANVAS, FOREGROUND_CANVAS), (0, 0, 0, 0))
    x = (FOREGROUND_CANVAS - resized.width) // 2
    y = (FOREGROUND_CANVAS - resized.height) // 2
    canvas.alpha_composite(resized, (x, y))
    return canvas


def _solid_mark(mark: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    output = Image.new("RGBA", mark.size, (*rgb, 0))
    output.putalpha(mark.getchannel("A"))
    return output


def _flat_composite(mark: Image.Image, size: int) -> Image.Image:
    if size != mark.width:
        mark = mark.resize((size, size), Image.Resampling.LANCZOS)
    background = Image.new("RGBA", (size, size), (*_hex_rgb(BACKGROUND_HEX), 255))
    background.alpha_composite(mark)
    return background.convert("RGB")


def _svg_path(commands: Iterable[tuple[str, tuple[float, ...]]]) -> str:
    parts: list[str] = []
    for command, values in commands:
        if command == "Z":
            parts.append("Z")
            continue
        parts.append(command + " " + " ".join(f"{value:g}" for value in values))
    return " ".join(parts)


def _write_vector_files(output_dir: Path) -> None:
    source_top = 240
    source_bottom = 1025
    scale = FOREGROUND_HEIGHT / (source_bottom - source_top)
    source_center_x = 622
    source_center_y = (source_top + source_bottom) / 2
    svg = f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <g fill="#000000" transform="translate(512 512) scale({scale:.9f}) translate({-source_center_x:g} {-source_center_y:g})">
    <path d="{_svg_path(DOT_PATH)}"/>
    <path d="{_svg_path(STEM_PATH)}"/>
  </g>
</svg>
'''
    (output_dir / "logo_monochrome_black_1024.svg").write_text(svg, encoding="utf-8")

    notification_xml = '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,2.4 C10.92,2.4 10.34,3.18 10.37,4.43 C10.40,5.67 11.10,6.50 12,6.53 C13.10,6.56 13.66,5.79 13.63,4.58 C13.59,3.27 13.02,2.43 12,2.4 Z" />
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M12,7.72 C10.50,7.72 9.61,8.56 9.57,10.07 C9.52,11.43 10.09,12.50 10.12,13.76 C10.15,15.03 9.49,16.61 9.60,18.93 C9.68,20.73 10.66,21.56 11.98,21.60 C13.48,21.64 14.35,20.69 14.33,18.86 C14.31,17.08 13.75,15.74 13.98,13.85 C14.18,12.29 14.47,11.04 14.39,9.98 C14.30,8.51 13.42,7.72 12,7.72 Z" />
</vector>
'''
    (output_dir / "ic_stat_here_i_am.xml").write_text(notification_xml, encoding="utf-8")


def build(source_path: Path, output_dir: Path) -> None:
    source = Image.open(source_path).convert("RGB")
    if source.size != (1254, 1254):
        raise ValueError(f"Expected the supplied 1254 x 1254 artwork, got {source.size}")

    output_dir.mkdir(parents=True, exist_ok=True)
    source_mask = _draw_source_mask(source.size)
    foreground = _centered_scaled_mark(source, source_mask)
    foreground.save(output_dir / "logo_foreground_1024.png", optimize=True)

    black = _solid_mark(foreground, (0, 0, 0))
    black.save(output_dir / "logo_monochrome_black_1024.png", optimize=True)

    _flat_composite(foreground, 512).save(
        output_dir / "logo_composite_512.png", optimize=True
    )
    _flat_composite(foreground, 1024).save(
        output_dir / "logo_composite_1024.png", optimize=True
    )

    ink_green = _solid_mark(foreground, _hex_rgb(INK_GREEN_HEX))
    _flat_composite(ink_green, 1024).save(
        output_dir / "logo_composite_ink_green_1024.png", optimize=True
    )

    raster_sizes = {"mdpi": 24, "hdpi": 36, "xhdpi": 48, "xxhdpi": 72, "xxxhdpi": 96}
    for density_name, canvas_size in raster_sizes.items():
        density = canvas_size / 24
        target_height = round(19.2 * density)
        bbox = foreground.getchannel("A").getbbox()
        assert bbox is not None
        cropped_alpha = foreground.getchannel("A").crop(bbox)
        target_width = max(1, round(cropped_alpha.width * target_height / cropped_alpha.height))
        alpha = cropped_alpha.resize((target_width, target_height), Image.Resampling.LANCZOS)
        icon = Image.new("RGBA", (canvas_size, canvas_size), (255, 255, 255, 0))
        mark = Image.new("RGBA", alpha.size, (255, 255, 255, 255))
        mark.putalpha(alpha)
        icon.alpha_composite(mark, ((canvas_size - target_width) // 2, (canvas_size - target_height) // 2))
        density_dir = output_dir / "notification_png" / density_name
        density_dir.mkdir(parents=True, exist_ok=True)
        icon.save(density_dir / "ic_stat_here_i_am.png", optimize=True)

    _write_vector_files(output_dir)
    (output_dir / "logo_background_color.txt").write_text(
        BACKGROUND_HEX + "\n", encoding="ascii"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the Here I am V3 logo asset pack")
    parser.add_argument("source", type=Path, help="Path to the supplied 1254 x 1254 logo artwork")
    parser.add_argument("output", type=Path, help="Destination directory for generated assets")
    args = parser.parse_args()
    build(args.source, args.output)


if __name__ == "__main__":
    main()
