#!/bin/bash
#SBATCH -J samtools_coverage
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=20g

# Print date and time
date_fmt="%-I:%M:%S %p (%a %d %b %Y)" # date format
date +"$date_fmt"
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
indiv_list="$5" # list of individual IDs

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
  checkfile="checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
else
  checkfile="checkpoints/$prefix.checkpoint"
fi
echo "Partition: $SLURM_JOB_PARTITION"

# Create output directory (if needed)
mkdir -p "$outdir"

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
# Input BAM file
uniq_id="${indiv_id}_$genome_base"
in_bam="$uniq_id.sorted.marked.bam"
# Input BAM index
in_bam_idx="$in_bam.bai"
# Verify input BAM & index exist in input directory
echo "Input alignment BAM: $indir/$in_bam"
echo "Input alignment BAM index: $indir/$in_bam_idx"
if [[ -f "$indir/$in_bam" ]] \
  && [[ -f "$indir/$in_bam_idx" ]]
then
  echo "Found input files in input directory: $indir"
else
  echo "Error - missing input BAM and/or index for $indiv_id"
  exit 1
fi
echo
# Output QC summary file named by ID
sam_cov="$uniq_id.sam_cov"

# Use temporary storage for computations
set -x
rsync --info=progress2 -ah "$indir/$in_bam" "$indir/$in_bam_idx" "$TMPDIR/"
set +x

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
module purge
conda activate samtools
samtools --version || exit 1

# Run samtools coverage
cmd=(
  samtools coverage
  "$TMPDIR/$in_bam"
)
echo "${cmd[*]} > $TMPDIR/$sam_cov"
if "${cmd[@]}" > "$TMPDIR/$sam_cov"
then
  check="pass"
  # Copy result from temporary storage
  set -x
  rsync --progress -ah "$TMPDIR/$sam_cov" "$outdir/"
  set +x
fi

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] && [[ -f "$outdir/$sam_cov" ]]
then
  echo "Creating checkpoint."
  touch "$checkfile"
  exit 0
else
  echo "Error - samtools coverage result for BAM ($in_bam) not found."
  echo "Checkpoint not created."
  exit 1
fi
