#!/bin/bash
#SBATCH -J bcftools_stats
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=100g

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

# Parse input VCF filename
in_vcf="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$vcf_list")"
in_vcf_basename="$(basename "$in_vcf")"
in_vcf_base="${in_vcf_basename%%.*}"
# Verify input file exists
[[ -f "$in_vcf" ]] \
  || { echo "Error - missing input VCF file ($in_vcf)"; exit 1; }
# Output evaluation QC file (name from input filename)
stats_file="$outdir/$in_vcf_base.bcftools.stats"

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load bcftools
conda activate bcftools
bcftools --version || exit 1

# Run bcftools stats
cmd=(
  bcftools stats
  -s
  "$in_vcf"
)
echo "${cmd[*]} > $stats_file"
"${cmd[@]}" > "$stats_file"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$stats_file" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - missing variant eval file ($stats_file) for VCF ($in_vcf)."
  echo "Checkpoint not created."
  exit 1
fi
