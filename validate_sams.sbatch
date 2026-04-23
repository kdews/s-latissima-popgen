#!/bin/bash
#SBATCH -J validate_sams
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
id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$id_file")"
# Input BAM file
in_bam="${id}_${genome_base}${pattern}"
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
  echo "Error - missing input BAM and/or index for $id"
  exit 1
fi
echo
# Output QC summary file named from ID
out_summary="$in_bam.validate.summary"

# Use temporary storage for computations
set -x
rsync --info=progress2 -ah "$indir/$in_bam" "$indir/$in_bam_idx" "$TMPDIR/"
set +x

# Define memory for GATK4
# Allocate from remaining memory (/tmp stores in RAM)
tmp_mem="$(du -m "$TMPDIR" | awk '{print $1}')"
mem="$(( SLURM_MEM_PER_NODE - tmp_mem ))"
# Minimum = 50% of memory remaining 
gatk_mem_min="$(( 5 * mem / 10 ))M"
# Maximum = 90% of memory remaining
gatk_mem_max="$(( 9 * mem / 10 ))M"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's ValidateSamFile in summary mode
cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  ValidateSamFile
  -M SUMMARY
  --MAX_RECORDS_IN_RAM 5000000
  -R "$genome_local_unzip"
  --TMP_DIR "$TMPDIR"
  -I "$TMPDIR/$in_bam"
  -O "$TMPDIR/$out_summary"
)
echo "${cmd[*]}"
"${cmd[@]}" && check="pass"

# Copy result from temporary storage
set -x
rsync --progress -ah "$TMPDIR/$out_summary" "$outdir/"
set +x

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] && [[ -f "$outdir/$out_summary" ]]
then
  echo "Creating checkpoint."
  touch "$checkfile"
  exit 0
else
  echo "Error - ValidateSamFile summary for BAM ($in_bam) not found."
  echo "Checkpoint not created."
  exit 1
fi