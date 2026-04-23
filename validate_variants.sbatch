#!/bin/bash
#SBATCH -J validate_variants
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=8g

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
id_file="$5" # index file (any text file list in indexer/)
pattern="$6" # SAM/BAM file ending pattern (e.g., .sorted.bam)

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

# Parse ID from index file
if [[ "$id_file" == "indexer/intervals_list.txt" ]]
then
  # Use Slurm ID for genomic intervals
  id="interval_${SLURM_ARRAY_TASK_ID}"
elif echo "$id_file" | grep -q "master"
then
  id="$id_file"
else
  id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$id_file")"
fi
# Input VCF file
in_vcf="${id}_${genome_base}${pattern}"
# Input VCF index
in_vcf_idx="${id}_${genome_base}${pattern}.tbi"
# Verify input BAM & index exist in input directory
echo "Input alignment VCF: $indir/$in_vcf"
echo "Input alignment VCF index: $indir/$in_vcf_idx"
if [[ -f "$indir/$in_vcf" ]] && [[ -f "$indir/$in_vcf_idx" ]]
then
  echo "Found input files in input directory: $indir"
else
  echo "Error - missing input VCF and/or index for $id"
  exit 1
fi
echo

# Use temporary storage for computations
set -x
rsync --info=progress2 -ah "$indir/$in_vcf" "$indir/$in_vcf_idx" "$TMPDIR/"
set +x

# Define memory for GATK4
# Allocate from remaining memory (/tmp stores in RAM)
tmp_mem="$(du -m "$TMPDIR" | awk '{print $1}')"
mem="$(( SLURM_MEM_PER_NODE - tmp_mem ))"
# Minimum = 50% of memory remaining 
gatk_mem_min="$(( 5 * mem / 10 ))M"
# Maximum = 90% of memory remaining
gatk_mem_max="$(( 9 * mem / 10 ))M"

# Set $filetype_flag to -gvcf, if needed
if echo "$in_vcf" | grep -Pq "\.g\.vcf|gvcf"
then
  echo "Treating input file ($in_vcf) as gVCF file."
  filetype_flag="-gvcf"
else
  echo "Treating input file ($in_vcf) as VCF file."
fi 

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's ValidateVariants
cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  ValidateVariants
  # Silence errors for ungenotyped alleles within multiallelic sites
  --validation-type-to-exclude ALLELES
  -R "$genome_local_unzip"
  --sequence-dictionary "$genome_dict"
  -V "$TMPDIR/$in_vcf"
)
# Add filetype flag (if needed)
[[ -n "$filetype_flag" ]] && cmd+=("$filetype_flag")
echo "${cmd[*]}"

# Checkpoint created if command has 0 exit code
mkdir -p checkpoints
if "${cmd[@]}"
then
  # Mark time at completion
  echo; date +"$date_fmt"; echo
  echo "Creating checkpoint."
  echo "$checkfile"
  touch "$checkfile"
  exit 0
else
  # Mark time at completion
  echo; date +"$date_fmt"; echo
  echo "Error - VCF ($in_vcf) did not pass validation. Check logs."
  echo "Checkpoint not created."
  exit 1
fi
