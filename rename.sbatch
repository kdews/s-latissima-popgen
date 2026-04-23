#!/bin/bash
#SBATCH -J rename
#SBATCH -o %x.log
#SBATCH --time=03:30:00
#SBATCH --mem=20g
#SBATCH --cpus-per-task=20

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
samples_list="$5" # file to save parsed sample IDs
scripts_dir="$6" # optional: directory containing scripts (MUST end in '/')

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
fi
echo "Partition: $SLURM_JOB_PARTITION"

# Create new output directory (if needed)
echo "Output directory: ${outdir}"
mkdir -p "$outdir"

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
if "${cmd[@]}" > "$og_file"
then
  # Run rename Python script
  cmd2=(
    python
    "${scripts_dir}rename_MO_KD.py"
    "$og_file"
    "$outdir"
    "$rsync_list"
  )
  echo "${cmd2[*]}"
  if "${cmd2[@]}"
  then
    # Load GNU parallel
    module purge
    module load ver/2506 gcc/14.3.0 parallel
    parallel --version || exit 1

    # Run rsync commands in parallel
    if parallel -j "$SLURM_CPUS_PER_TASK" < "$rsync_list"
    then
      # Make $samples_list from FASTQs in $outdir
      echo "Creating $samples_list"
      if find "$outdir" -type f -name "*.fastq.gz" \
        | sed -E 's|.*/||; s/_R[12]\.fastq.*//' \
        | sort -u > "$samples_list"
      then
        check="pass"
      fi
    fi
  fi
fi

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] && [[ -f "$samples_list" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - no samples list ($samples_list) found."
  echo "Checkpoint not created."
  exit 1
fi