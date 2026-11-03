"""Read one image from stdin and write a 160 px PNG thumbnail to stdout."""

import io
import sys
from PIL import Image, ImageOps

with Image.open(io.BytesIO(sys.stdin.buffer.read())) as source:
    source.seek(0)
    image = ImageOps.exif_transpose(source)
    image.thumbnail((160, 160), Image.Resampling.LANCZOS)
    output = io.BytesIO()
    image.save(output, format="PNG")
    sys.stdout.buffer.write(output.getvalue())
