#!/bin/bash
#SBATCH -J fastqc
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=08:00:00
#SBATCH --mem=5g
#SBATCH --cpus-per-task=2

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
samples_list="$5" # list of sample IDs

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
fi
echo "Partition: $SLURM_JOB_PARTITION"

# Parse sample ID and read filenames
sample_id="$(sed -n "${SLURM_ARRAY_TASK_ID}"p "$samples_list")"
reads1="$indir/${sample_id}_R1.fastq.gz"
reads2="$indir/${sample_id}_R2.fastq.gz"

# Create output directory (if needed)
echo "Creating output directory: $outdir"
mkdir -p "$outdir"

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load FastQC
conda activate fastqc
fastqc --version || exit 1

# Run FastQC
echo "Running FastQC on read files associated with sample ID: $sample_id"
echo "1: $reads1"
echo "2: $reads2"
cmd=(
  fastqc
  -t "$SLURM_CPUS_PER_TASK"
  # Give memory in MB (default unit for Slurm and FastQC)
  --memory "$SLURM_MEM_PER_NODE"
  -o "$outdir"
  "$reads1"
  "$reads2"
)
echo "${cmd[*]}"
"${cmd[@]}" && check="pass"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] \
  && [[ -f "$outdir/${sample_id}_R1_fastqc.zip" ]] \
  && [[ -f "$outdir/${sample_id}_R2_fastqc.zip" ]] \
  && [[ -f "$outdir/${sample_id}_R1_fastqc.html" ]] \
  && [[ -f "$outdir/${sample_id}_R2_fastqc.html" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - not all FastQC files created for sample ID: $sample_id"
  echo "Checkpoint not created."
  exit 1
fi
