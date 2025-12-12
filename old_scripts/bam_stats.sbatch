#!/bin/bash
#SBATCH -J bam_stats
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=30g
#SBATCH --cpus-per-task=12

# Log Slurm job details
echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
echo "Partition: $SLURM_JOB_PARTITION"

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
# Verify input file exists
[[ -f "$indir/$in_bam" ]] \
  || { echo "Error - missing input file for $indiv_id"; exit 1; }
# Output QC files named by ID
stats_file="$uniq_id.stats"

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
samtools --version || exit 1

# Run samtools stats
cmd=(
  samtools stats
  -@ "$SLURM_CPUS_PER_TASK"
  -r "$genome_local_unzip"
  "$indir/$in_bam"
)
echo "${cmd[*]} > $outdir/$stats_file"
"${cmd[@]}" > "$outdir/$stats_file"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$stats_file" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - missing stats file ($stats_file) for BAM ($in_bam)."
  echo "Checkpoint not created."
  exit 1
fi
