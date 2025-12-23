#!/bin/bash
#SBATCH -J sort_vcf
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=00:30:00
#SBATCH --mem=25g

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
fi
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
intervals_list="$5" # text file listing interval filenames

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

# Parse interval
interval="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$intervals_list")"
# Parse input VCF name
uniq_id="interval_${SLURM_ARRAY_TASK_ID}_$genome_base"
in_vcf="$indir/$uniq_id.vcf.gz"
# Output VCF named from parsed input filename
out_vcf="$outdir/$uniq_id.sorted.vcf.gz"
# Log job details
echo
echo "Genomic interval: $interval"
echo "Input VCF: $in_vcf"
echo "Out VCF: $out_vcf"
echo

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Define memory for GATK4
# Minimum = 50% of memory
gatk_mem_min="$(( 5 * SLURM_MEM_PER_NODE / 10 ))M"
# Maximum = 90% of memory
gatk_mem_max="$(( 9 * SLURM_MEM_PER_NODE / 10 ))M"

# Run GATK4's SortVcf
cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  SortVcf
  --MAX_RECORDS_IN_RAM 5000000
  -R "$genome_local_unzip"
  -I "$in_vcf"
  -O "$out_vcf"
  # Give TMPDIR environment variable (Slurm sets this)
  --TMP_DIR "$TMPDIR"
)
echo "${cmd[*]}"
"${cmd[@]}" && check="pass"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] && [[ -f "$out_vcf" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - sorted VCF ($out_vcf) not found for $in_vcf"
  echo "Checkpoint not created."
  exit 1
fi
