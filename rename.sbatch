#!/bin/bash
#SBATCH --mem=20gb
#SBATCH --time=03:30:00
#SBATCH --cpus-per-task=20

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
genome="$4" # genome FASTA
samples_list="$5" # file to save parsed sample IDs
scripts_dir="$6" # optional: directory containing scripts (MUST end in '/')

# Output
logdir="${prefix}_logs" # log directory
og_file="$logdir/original_filenames.txt" # list of original FASTQ paths
rsync_list="$logdir/rsync_list.txt" # list of rsync commands

# List original FASTQ paths
cmd=(
   find
   "$indir"
   -mindepth 2
   -maxdepth 2
   -type f
   -name "*.fastq.gz"
   -exec realpath -e {} \;
)
echo "${cmd[*]} > $og_file"
"${cmd[@]}" > "$og_file"
unset cmd

# Create new output directory (if needed)
echo "Output directory: ${outdir}"
mkdir -p "$outdir"

# Run rename Python script
cmd=(
    python
    "${scripts_dir}rename_MO_KD.py"
    "$og_file"
    "$outdir"
    "$rsync_list"
)
echo "${cmd[*]}"
"${cmd[@]}"
unset cmd

module purge
module load ver/2506 gcc/14.3.0 parallel
parallel --version
parallel -j "$SLURM_CPUS_PER_TASK" < "$rsync_list"

# Make $samples_list from FASTQs in $outdir
echo "Creating $samples_list"
find "$outdir" -type f -name "*.fastq.gz"    \
    | sed -E 's|.*/||; s/_R[12]\.fastq.*//' \
    | sort -u > "$samples_list"

# Checkpoint
mkdir -p checkpoints
echo "Creating checkpoint."
touch "checkpoints/${prefix}.checkpoint"