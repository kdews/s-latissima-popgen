#!/bin/bash
#SBATCH -J collect_alignment_summary_metrics
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

# Parse sample ID
sample_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$samples_list")"
# Input BAM file
in_bam="${sample_id}_$genome_base.sorted.bam"
# Output QC file named from sample ID
align_metrics="${sample_id}_$genome_base.collect_alignment_summary.metrics"

# Define memory for GATK4 (90% of total)
gatk_mem="$(( 9 * SLURM_MEM_PER_NODE / 10 ))M"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Use temporary storage for computations
echo "rsync --progress $indir/$in_bam $TMPDIR/"
rsync --progress "$indir/$in_bam" "$TMPDIR/"

# Run GATK4 CollectAlignmentSummaryMetrics on HISAT2 alignmnets
cmd=(
  gatk
  --java-options "-Xmx$gatk_mem"
  CollectAlignmentSummaryMetrics
  -R "$genome_local_unzip"
  --TMP_DIR "$TMPDIR"
  -I "$TMPDIR/$in_bam"
  -O "$TMPDIR/$align_metrics"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Copy result from temporary storage
echo "rsync --progress $TMPDIR/$align_metrics $outdir/"
rsync --progress "$TMPDIR/$align_metrics" "$outdir/"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$align_metrics" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - Alignment Summay Metrics file ($align_metrics) for BAM ($in_bam) not found."
  echo "Checkpoint not created."
  exit 1
fi
