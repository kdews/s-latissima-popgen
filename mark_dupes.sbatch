#!/bin/bash
#SBATCH -J mark_dupes
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=02:00:00
#SBATCH --mem=15gb

# Print date and time
date
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

# Source genome config
if [[ -f "$genome_config" ]]
then
  source "$genome_config"
else
  echo "Error on source of genome config: $genome_config"
  exit 1
fi

# Parse sample ID
sample_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$samples_list")"
# Input sorted BAM file
in_bam="$indir/${sample_id}_$genome_base.sorted.bam"
# Output marked BAM file
out_bam="$outdir/${sample_id}_$genome_base.sorted.marked.bam"
# QC metrics for marked duplicates
dupe_metrics="$qc_dir/${sample_id}_$genome_base.mark_dupes.metrics"

# Define memory for GATK4 (90% of total)
gatk_mem="$(( 9 * SLURM_MEM_PER_NODE / 10 ))M"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's MarkDuplicates
cmd=(
  gatk
  --java-options "-Xms$gatk_mem -Xmx$gatk_mem"
  MarkDuplicates
  -R "$genome_local_unzip"
  --tmp-dir "$TMPDIR"
  -I" $in_bam"
  -O "$out_bam"
  -M "$dupe_metrics"
  --VALIDATION_STRINGENCY LENIENT
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$out_bam" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - duplicate-marked BAM not found for sample ID: $sample_id"
  echo "Checkpoint not created."
  exit 1
fi