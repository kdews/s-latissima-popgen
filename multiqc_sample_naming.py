import os
from pathlib import Path

yaml_fn = "multiqc_rename_samples.tsv"
qc_dir = Path("quality_control")
yaml_lines = []

# Identify the "biological sample ID" for each file
for f in sorted(qc_dir.iterdir()):
    if f.suffix in [".txt", ".zip", ".summary", ".stats"]:
        stem_raw = f.stem
        stem = stem_raw.split(".")[0]
        # Split on underscore
        parts = stem.split("_")
        if stem.startswith("I") or stem.startswith("J"):        
            # If library ID
            bio_sample = "_".join(parts[:6])
        else:
            # If sample ID
            bio_sample = parts[0]
        yaml_lines.append(f"{stem}\t{bio_sample}")

# Remove duplicates and sort
yaml_lines = sorted(set(yaml_lines))

with open(yaml_fn, "w") as out:
    out.write("\n".join(yaml_lines))
