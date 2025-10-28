#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=05:00:00
#SBATCH --cpus-per-task=15

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
genome="$4" # genome FASTA
samples_list="$5" # list of sample IDs
qc_dir="$6" # directory to write QC output

# Create output and QC directories (if needed)
mkdir -p "$outdir"
mkdir -p "$qc_dir"

# Parse sample ID and read filenames
sample_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$samples_list")"
reads1="$indir/${sample_id}_R1.fastq.gz"
reads2="$indir/${sample_id}_R2.fastq.gz"

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -a "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load Trim Galore!
conda activate trimgalore
trim_galore --version

# Run Trim Galore!
echo "Running Trim Galore! on read files associated with sample ID: $sample_id"
echo "1: $reads1"
echo "2: $reads2"
cmd=(
    trim_galore
    --paired
    --phred33
    --output_dir "$qc_dir"
    --length 36
    --stringency 1
    -e 0.1
    -j 4
    --fastqc_args "-t $SLURM_CPUS_PER_TASK"
    "$reads1"
    "$reads2"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoint
mkdir -p checkpoints
if [[ "$(find "$qc_dir" -type f -name "${sample_id}*val*" | wc -l)" -eq 6 ]]
then
    echo "Read trimming and FastQC of trimmed reads completed for sample ID: $sample_id"
    echo "Creating checkpoint."
    mv "$qc_dir/${sample_id}"*"fq.gz" "$outdir"
    touch "checkpoints/${prefix}_${SLURM_ARRAY_TASK_ID}.checkpoint"
    exit 0
else
    echo "Error trimming reads for sample ID: $sample_id"
    echo "Checkpoint not created."
    exit 1
fi
