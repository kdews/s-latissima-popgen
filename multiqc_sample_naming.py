import os
from pathlib import Path

yaml_fn = "rename_samples.yaml"
qc_dir = Path("quality_control")
yaml_lines = []

for f in qc_dir.iterdir():
    if f.suffix in [".txt", ".html", ".zip"]:
        stem = f.stem
        # Split on underscore
        parts = stem.split("_")
        # Identify the "biological sample ID"
        # Here we take everything up to the first numeric lane/library index or barcode (usually at position 4 or 5)
        # Adjust the number 4 below if your IDs are longer
        bio_sample = "_".join(parts[:4])
        yaml_lines.append(f"{stem}: {bio_sample}")

# Remove duplicates and sort
yaml_lines = sorted(set(yaml_lines))

with open(yaml_fn, "w") as out:
    out.write("\n".join(sorted(set(yaml_lines))))
