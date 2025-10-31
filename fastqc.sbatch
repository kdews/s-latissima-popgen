#!/bin/bash
#SBATCH --mem=5gb
#SBATCH --time=08:00:00
#SBATCH --cpus-per-task=12

# Print date and time
date
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
samples_list="$5" # list of sample IDs

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

# Load FASTQC
conda activate fastqc
fastqc --version || exit 1

# Run FASTQC
echo "Running FASTQC on read files associated with sample ID: $sample_id"
echo "1: $reads1"
echo "2: $reads2"
cmd=(
  fastqc
  -t "$SLURM_CPUS_PER_TASK"
  -o "$outdir"
  "$reads1"
  "$reads2"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/${sample_id}_R1_fastqc.zip" ]] && \
  [[ -f "$outdir/${sample_id}_R2_fastqc.zip" ]] && \
  [[ -f "$outdir/${sample_id}_R1_fastqc.html" ]] && \
  [[ -f "$outdir/${sample_id}_R2_fastqc.html" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_${SLURM_ARRAY_TASK_ID}.checkpoint"
  exit 0
else
  echo "Error - not all FastQC files created for sample ID: $sample_id"
  echo "Checkpoint not created."
  exit 1
fi
