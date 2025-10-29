#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=05:00:00

prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
genome_config="$4"
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

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version

# Run GATK4's ValidateSamFile in summary mode
cmd=(
    gatk ValidateSamFile
    -M SUMMARY
    -R "$genome_local_unzip"
    -I "$infile"
    -O "$out_summary"
)
echo "${cmd[*]}"
"${cmd[@]}"

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