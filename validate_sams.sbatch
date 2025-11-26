#!/bin/bash
#SBATCH -J validate_sams
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=15g

# Log Slurm job details
echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
echo "Partition: $SLURM_JOB_PARTITION"

# Print date and time
date
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
id_file="$5" # index file (any text file list in indexer/)
pattern="$6" # SAM/BAM file ending pattern (e.g., .sorted.bam)

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
# Verify input file exists
[[ -f "$infile" ]] || { echo "Error - missing input file for $id"; exit 1; }
infile_basename="$(basename "$infile")"
# Output QC summary file named from ID
out_summary="$infile_basename.validate.summary"

# Use temporary storage for computations
echo "rsync --progress $infile $TMPDIR/"
rsync --progress "$infile" "$TMPDIR/"

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
  -I "$TMPDIR/$infile_basename"
  -O "$TMPDIR/$out_summary"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Copy result from temporary storage
echo "rsync --progress $TMPDIR/$out_summary $outdir/"
rsync --progress "$TMPDIR/$out_summary" "$outdir/"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$out_summary" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - ValidateSamFile summary for BAM ($infile) not found."
  echo "Checkpoint not created."
  exit 1
fi