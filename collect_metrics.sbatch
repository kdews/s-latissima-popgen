#!/bin/bash
#SBATCH -J collect_metrics
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=15g

# Log Slurm job details
echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
echo "Partition: $SLURM_JOB_PARTITION"

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
# Verify input file exists
[[ -f "$indir/$in_bam" ]] \
  || { echo "Error - missing input file for $sample_id"; exit 1; }
# Output QC files named from sample ID
align_metrics="${sample_id}_$genome_base.collect_alignment_summary.metrics"
wgs_metrics="${sample_id}_$genome_base.collect_wgs.metrics"

# Use temporary storage for computations
echo "rsync --progress $indir/$in_bam $TMPDIR/"
rsync --progress "$indir/$in_bam" "$TMPDIR/"

# Define memory for GATK4
# Allocate from remaining memory (/tmp stores in RAM)
file_mem="$(du -m "$TMPDIR/$in_bam" | awk '{print $1}')"
mem="$(( SLURM_MEM_PER_NODE - file_mem ))"
# Minimum = 50% of memory remaining 
gatk_mem_min="$(( 5 * mem / 10 ))M"
# Maximum = 90% of memory remaining
gatk_mem_max="$(( 9 * mem / 10 ))M"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4 CollectAlignmentSummaryMetrics on HISAT2 alignmnets
align_cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  CollectAlignmentSummaryMetrics
  --MAX_RECORDS_IN_RAM 5000000
  -R "$genome_local_unzip"
  --TMP_DIR "$TMPDIR"
  -I "$TMPDIR/$in_bam"
  -O "$TMPDIR/$align_metrics"
)
echo "${align_cmd[*]}"
"${align_cmd[@]}"

# Run GATK4's CollectWgsMetrics on HISAT2 alignmnets
wgs_cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  CollectWgsMetrics
  --USE_FAST_ALGORITHM
  --MAX_RECORDS_IN_RAM 5000000
  --READ_LENGTH 150
  -R "$genome_local_unzip"
  --TMP_DIR "$TMPDIR"
  -I "$TMPDIR/$in_bam"
  -O "$TMPDIR/$wgs_metrics"
)
echo "${wgs_cmd[*]}"
"${wgs_cmd[@]}"

# Copy results from temporary storage
echo "rsync --progress $TMPDIR/$align_metrics $TMPDIR/$wgs_metrics $outdir/"
rsync --progress "$TMPDIR/$align_metrics" "$TMPDIR/$wgs_metrics" "$outdir/"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$align_metrics" ]] && [[ -f "$outdir/$wgs_metrics" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - missing metrics QC files for BAM ($in_bam). Expected files:"
  echo "$outdir/$align_metrics"
  echo "$outdir/$wgs_metrics"
  echo "Checkpoint not created."
  exit 1
fi
