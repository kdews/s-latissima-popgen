#!/bin/bash
#SBATCH -J trim_galore
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=8g
#SBATCH --cpus-per-task=15

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
fi
echo "Partition: $SLURM_JOB_PARTITION"

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
qc_dir="$6" # directory to write QC output

# Create output and QC directories (if needed)
mkdir -p "$outdir"
mkdir -p "$qc_dir"

# Parse sample ID and read filenames
sample_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$samples_list")"
reads1="$indir/${sample_id}_R1.fastq.gz"
reads2="$indir/${sample_id}_R2.fastq.gz"
# Output trimmed reads
trim1="$outdir/${sample_id}_R1_val_1.fq.gz"
trim2="$outdir/${sample_id}_R2_val_2.fq.gz"
# Output trimming reports
report1="$outdir/${sample_id}_R1.fastq.gz_trimming_report.txt"
report2="$outdir/${sample_id}_R2.fastq.gz_trimming_report.txt"

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load Trim Galore!
conda activate trim_galore
trim_galore --version || exit 1

# Run Trim Galore!
echo
echo "Running Trim Galore! on read files associated with sample ID: $sample_id"
echo "1: $reads1"
echo "2: $reads2"
echo
cmd=(
  trim_galore
  --paired
  --output_dir "$outdir"
  --length 36
  --stringency 1
  -e 0.1
  # "--cores 4 could be a sweet spot, anything above has diminishing returns"
  --cores 4
  --fastqc_args "-t $SLURM_CPUS_PER_TASK -o $qc_dir"
  "$reads1"
  "$reads2"
)
echo "${cmd[*]}"
"${cmd[@]}" && check="pass"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] && [[ -f "$trim1" ]] && [[ -f "$trim2" ]]
then
  echo "Trimming and FastQC of trimmed reads completed for sample ID: $sample_id"
  if [[ -f "$report1" ]] && [[ -f "$report2" ]]
  then
    echo "Moving trimming reports to QC directory ($qc_dir/):"
    echo "$report1"
    echo "$report2"
    mv "$report1" "$qc_dir/"
    mv "$report2" "$qc_dir/"
  else
    echo "No trimming reports found for sample ID: $sample_id"
  fi
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error trimming reads for sample ID: $sample_id"
  echo "Checkpoint not created."
  exit 1
fi