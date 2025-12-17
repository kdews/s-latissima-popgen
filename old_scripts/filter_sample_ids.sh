#!/bin/bash

# Source pipeline variables
source s-latissima-popgen/pipeline.conf

# Create array from sample ID list
mapfile -t ids < "$samples_list"

# Rename original sample ID list file
samples_list_all="${samples_list%%.*}_all.txt"
mv "$samples_list" "$samples_list_all"
all_ids="$(wc -l < indexer/samples_list_all.txt)"
echo "$all_ids sample IDs in $samples_list saved to $samples_list_all"

# Write filtered sample IDs to $samples_list
for id in "${ids[@]}"
do
  # Check for paired-end FASTQ files for each sample ID
  if [[ "$(find "wgs" -type f -name "${id}*.fastq.gz" | wc -l)" -eq 2 ]]
  then
    echo "$id"
  fi
done > "$samples_list"

# Log number of samples filtered
pass_ids="$(wc -l < indexer/samples_list.txt)"
echo "$(( all_ids - pass_ids )) sample IDs without paired-end reads."
echo "After filtering, $pass_ids sample IDs written to $samples_list"