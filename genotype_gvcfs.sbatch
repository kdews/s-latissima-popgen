#!/bin/bash
#SBATCH -J genotype_gvcfs
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=04:00:00
#SBATCH --mem=50g

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
indir="$3" # parent input directory containing subdirectories
outdir="$4" # output directory
intervals_list="$5" # text file listing interval filenames

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
fi
echo "Partition: $SLURM_JOB_PARTITION"

# Create output directory (if needed)
mkdir -p "$outdir"

# Subdirectory for this job step
genomicsDB="$indir/interval_$SLURM_ARRAY_TASK_ID"
# Verify input GenomicsDB exists
[[ -d "$genomicsDB" ]] || { echo "Error - no GenomicsDB: $genomicsDB"; exit 1; }

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
# Output VCF named based on interval
out_vcf="$outdir/interval_${SLURM_ARRAY_TASK_ID}_$genome_base.vcf.gz"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Define memory for GATK4 (leave more for $TMPDIR cache)
# Minimum = 20% of memory
gatk_mem_min="$(( 2 * SLURM_MEM_PER_NODE / 10 ))M"
# Maximum = 30% of memory
gatk_mem_max="$(( 3 * SLURM_MEM_PER_NODE / 10 ))M"

# Run GATK4's GenotypeGVCFs with GenomicsDBImport option
cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  GenotypeGVCFs
  -ploidy 1
  -R "$genome_local_unzip"
  --sequence-dictionary "$genome_dict"
  -L "$interval"
  -V "gendb://$genomicsDB"
  -O "$out_vcf"
  # Give TMPDIR environment variable (Slurm sets this)
  --tmp-dir "$TMPDIR"
  --genomicsdb-shared-posixfs-optimizations
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
  echo "Error - output VCF file ($out_vcf) not found."
  echo "Checkpoint not created."
  exit 1
fi
