#!/bin/bash
#SBATCH -J rename
#SBATCH -o %x.log
#SBATCH --time=03:30:00
#SBATCH --mem=20g
#SBATCH --cpus-per-task=20

# Log Slurm job details
echo "Partition: $SLURM_JOB_PARTITION"

# Print date and time
date
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
samples_list="$5" # file to save parsed sample IDs
scripts_dir="$6" # optional: directory containing scripts (MUST end in '/')

# Output
og_file="$outdir/original_filenames.txt" # list of original FASTQ paths
rsync_list="$outdir/rsync_list.txt" # list of rsync commands

# List original FASTQ paths
cmd=(
  find
  "$indir"
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

# Load GNU parallel
module purge
module load ver/2506 gcc/14.3.0 parallel
parallel --version || exit 1

# Run rsync commands in parallel
parallel -j "$SLURM_CPUS_PER_TASK" < "$rsync_list"

# Make $samples_list from FASTQs in $outdir
echo "Creating $samples_list"
find "$outdir" -type f -name "*.fastq.gz" \
  | sed -E 's|.*/||; s/_R[12]\.fastq.*//' \
  | sort -u > "$samples_list"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$samples_list" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - no samples list ($samples_list) found."
  echo "Checkpoint not created."
  exit 1
fi