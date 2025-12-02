#!/bin/bash
#SBATCH -J sort_vcf
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=00:30:00
#SBATCH --mem=25g

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
vcf_list="$5" # list of genotyped VCF files

# Name temp directory after job name
tempdir="${prefix}_tmp"

# Create temp directory (if needed)
mkdir -p "$tempdir"

# Source genome config
if [[ -f "$genome_config" ]]
then
  source "$genome_config"
else
  echo "Error on source of genome config: $genome_config"
  exit 1
fi

# Parse input VCF name
in_vcf="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$vcf_list")"
in_vcf_basename="$(basename "$in_vcf")"
in_vcf_base="${in_vcf_basename%%.*}"
# Output VCF named from parsed input filename
out_vcf="$outdir/$in_vcf_base.sorted.vcf.gz"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's SortVcf
cmd=(
  gatk SortVcf
  --java-options "-Xms20g -Xmx20g"
  -R "$genome_local_unzip"
  -I "$in_vcf"
  -O "$out_vcf"
  --TMP_DIR "$tempdir"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$out_vcf" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - sorted VCF ($out_vcf) not found for $in_vcf"
  echo "Checkpoint not created."
  exit 1
fi
