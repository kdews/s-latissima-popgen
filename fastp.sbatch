#!/bin/bash
#SBATCH -J fastp
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=20g
#SBATCH --cpus-per-task=15

# Print date and time
date_fmt="%-I:%M:%S %p (%a %d %b %Y)"
date +"$date_fmt"
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
samples_list="$5" # list of sample IDs
qc_dir="$6" # directory to write QC output

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
fi
echo "Partition: $SLURM_JOB_PARTITION"

# Create output and QC directories
mkdir -p "$outdir"
mkdir -p "$qc_dir"

# Parse sample ID and read filenames
sample_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$samples_list")"
reads1="${sample_id}_R1.fastq.gz"
reads2="${sample_id}_R2.fastq.gz"
# Output trimmed reads
trim1="${sample_id}_R1_fastp.fastq.gz"
trim2="${sample_id}_R2_fastp.fastq.gz"
# fastp QC reports
html_report="${sample_id}_fastp.html"
json_report="${sample_id}_fastp.json"

# Use temporary storage for computations
set -x
rsync --info=progress2 "$indir/$reads1" "$indir/$reads2" "$TMPDIR/"
set +x

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
then
  source "$cond"
else
  echo "Error sourcing $cond"
  exit 1
fi

# Activate fastp environment
conda activate fastp
fastp --version || exit 1

# Run fastp
echo
echo "Running fastp on read files associated with sample ID: $sample_id"
echo "1: $reads1"
echo "2: $reads2"
echo

cmd=(
  fastp
  --in1 "$TMPDIR/$reads1"
  --in2 "$TMPDIR/$reads2"
  --out1 "$TMPDIR/$trim1"
  --out2 "$TMPDIR/$trim2"
  --thread "$SLURM_CPUS_PER_TASK"
  --detect_adapter_for_pe
  --trim_poly_g
  --poly_g_min_len 8
  --cut_right
  --cut_right_window_size 4
  --cut_right_mean_quality 28
  --length_required 36
  --overrepresentation_analysis
  --html "$TMPDIR/$html_report"
  --json "$TMPDIR/$json_report"
)
echo "${cmd[*]}"
if "${cmd[@]}"
then
  # Copy trimmed reads to output dir and reports to QC dir
  set -x
  rsync --info=progress2 "$TMPDIR/$trim1" "$TMPDIR/$trim2" "$outdir/"
  rsync --info=progress2 "$TMPDIR/$html_report" "$TMPDIR/$json_report" "$qc_dir/"
  set +x

  echo "Cleaning temporary directory: $TMPDIR"
  rm -rf "$TMPDIR"/*

  # Load FastQC
  conda activate fastqc
  fastqc --version || exit 1

  # Define memory for FastQC (must be < 10000 MB)
  if (( SLURM_MEM_PER_NODE > 10000 ))
  then
    f_mem=10000
  else
    f_mem="$SLURM_MEM_PER_NODE"
  fi

  # Run FastQC on trimmed reads
  echo "Running FastQC on trimmed read files associated with sample ID: $sample_id"
  echo "1: $outdir/$trim1"
  echo "2: $outdir/$trim2"
  echo
  
  f_cmd=(
    fastqc
    -t 2
    # Give memory in MB (default unit for Slurm and FastQC)
    --memory "$f_mem"
    -o "$qc_dir"
    "$outdir/$trim1"
    "$outdir/$trim2"
  )
  echo "${f_cmd[*]}"
  if "${f_cmd[@]}"
  then
    # Mark time at completion
    echo
    date +"$date_fmt"
    echo

    # Checkpoint
    mkdir -p checkpoints
    if [[ -f "$outdir/$trim1" ]] \
      && [[ -f "$outdir/$trim2" ]]
    then
      echo "fastp trimming completed for sample ID: $sample_id"
      echo "QC reports:"
      echo "$qc_dir/$html_report"
      echo "$qc_dir/$json_report"
      echo
      echo "FastQC reports:"
      echo "$qc_dir/${sample_id}_R1_fastp_fastqc.zip"
      echo "$qc_dir/${sample_id}_R2_fastp_fastqc.zip"
      echo "$qc_dir/${sample_id}_R1_fastp_fastqc.html"
      echo "$qc_dir/${sample_id}_R2_fastp_fastqc.html"
      echo
      echo "Creating checkpoint."
      touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
      exit 0
    else
      echo "Error trimming reads for sample ID: $sample_id"
      echo "Checkpoint not created."
      exit 1
    fi
  fi
fi

