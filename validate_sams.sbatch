#!/bin/bash
#SBATCH -J validate_sams
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --mem=8gb
#SBATCH --time=05:00:00

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
infile_basename="$(basename "$infile")"
# Output QC summary file named from ID
out_summary="$outdir/$infile_basename.validate.summary"

# Define memory for GATK4 (90% of total)
gatk_mem_min="$(( 3 * SLURM_MEM_PER_NODE / 10 ))M"
gatk_mem_max="$(( 9 * SLURM_MEM_PER_NODE / 10 ))M"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# # Use temporary storage for computations
# echo "rsync --progress $infile $TMPDIR/"
# rsync --progress "$infile" "$TMPDIR/"

# Run GATK4's ValidateSamFile in summary mode
cmd=(
  gatk
  --java-options "-Xmx $gatk_mem_min -Xmx$gatk_mem_max"
  ValidateSamFile
  -M SUMMARY
  --MAX_RECORDS_IN_RAM 5000000
  -R "$genome_local_unzip"
  --TMP_DIR "$TMPDIR"
  -I "$infile"
  -O "$out_summary"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$out_summary" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - ValidateSamFile summary for BAM ($infile) not found."
  echo "Checkpoint not created."
  exit 1
fi