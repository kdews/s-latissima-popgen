#!/bin/bash
#SBATCH --mem=1g
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=5

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
indiv_list="$5" # list of individual IDs

# Source genome config
if [[ -f "$genome_config" ]]
then
    source "$genome_config"
else
    echo "Error on source of genome config: $genome_config"
    exit 1
fi

# Parse individual ID
indiv_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$indiv_list")"
# Input BAM file named from ID
in_bam="$indir/${indiv_id}_$genome_base.sorted.marked.merged.bam"

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load samtools
conda activate samtools
samtools --version

# Index BAM with samtools
cmd=(
    samtools index
    -@ "$SLURM_CPUS_PER_TASK"
    "$in_bam"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoint
mkdir -p checkpoints
if [[ -f "$in_bam.bai" ]]
then
    echo "Creating checkpoint."
    touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
    exit 0
else
    echo "Error - no BAM index ($in_bam.bai) found."
    echo "Checkpoint not created."
    exit 1
fi
