#!/bin/bash

for f in quality_control/*R[12]_fastqc.zip
do
  echo -n "$(basename "$f"): "
  # unzip -p "$f" "*/fastqc_data.txt" | grep "Total Bases" | cut -f2
  unzip -p "$f" "*/fastqc_data.txt" | grep "Total Bases" | awk '{print $NF}'
done
