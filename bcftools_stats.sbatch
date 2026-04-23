#!/bin/bash
#SBATCH -J bcftools_stats
#SBATCH -o %x.log
#SBATCH --time=05:00:00
#SBATCH --mem=10g
#SBATCH --cpus-per-task=12

# -e  exit on error
# -o pipefail  catch errors in pipes
set -eo pipefail

# Print date and time
date_fmt="%-I:%M:%S %p (%a %d %b %Y)" # date format
date +"$date_fmt"
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
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

# Input VCF filename
year="$(date +%Y)" # current year
in_vcf_base="master_${year}_$genome_base"
in_vcf="$indir/$in_vcf_base.vcf.gz"
# Verify input file exists
[[ -f "$in_vcf" ]] || { echo "Error - missing input VCF ($in_vcf)"; exit 1; }
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
  --threads "$SLURM_CPUS_PER_TASK"
  # -s -
  -F "$genome_local_unzip"
  "$in_vcf"
)
echo "${cmd[*]} > $stats_file"
"${cmd[@]}" > "$stats_file" && check="pass"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] && [[ -f "$stats_file" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - missing variant eval file ($stats_file) for VCF ($in_vcf)."
  echo "Checkpoint not created."
  exit 1
fi
