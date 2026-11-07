#!/usr/bin/env python3
import argparse
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ppm")
    parser.add_argument("png", nargs="?")
    args = parser.parse_args()

    try:
        from PIL import Image
    except ImportError:
        raise SystemExit("Pillow is required: python3 -m pip install pillow")

    ppm = Path(args.ppm)
    png = Path(args.png) if args.png else ppm.with_suffix(".png")
    Image.open(ppm).save(png)
    print(png)


if __name__ == "__main__":
    main()
