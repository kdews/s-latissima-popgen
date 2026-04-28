#!/bin/bash
#SBATCH -J hisat2_build
#SBATCH -o %x.log
#SBATCH --time=01:00:00
#SBATCH --mem=40g
#SBATCH --cpus-per-task=12

# Print date and time
date_fmt="%-I:%M:%S %p (%a %d %b %Y)" # date format
date +"$date_fmt"
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory

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

# Copy and uncompress input genome file to $indir (if needed)
if [[ ! -f "$genome_local_unzip" ]]
then
  if [[ ! -f "$genome_local" ]]
  then
    echo "Copying genome ($genome) to: $(realpath -e "$indir")"
    rsync -avc "$genome" "$indir/"
  fi
  module purge
  module load ver/2506 gcc/14.3.0 gzip/1.14
  echo "Unzipping genome: $genome_local"
  gunzip "$genome_local"
  module purge
fi

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load HISAT2
conda activate hisat2
hisat2-build --version || exit 1

# Start HISAT2-build run
echo "Running HISAT2-build on genome file: $genome_local_unzip"
cmd=(
  hisat2-build
  -p "$SLURM_CPUS_PER_TASK"
  "$genome_local_unzip"
  "$ht2_idx"
)
echo "${cmd[*]}"
"${cmd[@]}" && check="pass"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] \
  && (( $(find "$outdir" -type f -name "$genome_base.*.ht2" | wc -l) > 0 ))
then  
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - HISAT2 index files ($ht2_idx.*.ht2) not found."
  echo "Checkpoint not created."
  exit 1
fi
