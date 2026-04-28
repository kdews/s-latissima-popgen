#!/bin/bash
#SBATCH -J validate_sams_verbose
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=8g

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
# Parse input filename (must have underscore (_) following unique ID)
infile="$(find "$indir" -type f -name "*${id}_*$pattern")"
infile_basename="$(basename "$infile")"
# Output QC summary file named from ID
out_summary="$infile_basename.validate.verbose"

# Use temporary storage for computations
set -x
rsync --progress -ah "$infile" "$TMPDIR/"
set +x

# Define memory for GATK4
# Allocate from remaining memory (/tmp stores in RAM)
file_mem="$(du -m "$TMPDIR/$infile_basename" | awk '{print $1}')"
mem="$(( SLURM_MEM_PER_NODE - file_mem ))"
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
  -M VERBOSE
  --MAX_RECORDS_IN_RAM 5000000
  -R "$genome_local_unzip"
  --TMP_DIR "$TMPDIR"
  -I "$TMPDIR/$infile_basename"
  -O "$TMPDIR/$out_summary"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Copy result from temporary storage
set -x
rsync --progress -ah "$TMPDIR/$out_summary" "$outdir/"
set +x

# Mark time at completion
echo; date +"$date_fmt"; echo