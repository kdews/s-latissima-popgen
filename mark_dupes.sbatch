#!/bin/bash
#SBATCH -J mark_dupes
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=02:00:00
#SBATCH --mem=100g
#SBATCH --cpus-per-task=8

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
in_bam="${sample_id}_$genome_base.sorted.bam"
# Verify input file exists
[[ -f "$indir/$in_bam" ]] \
  || { echo "Error - missing input file for $sample_id"; exit 1; }
# Output marked BAM file
out_bam="${sample_id}_$genome_base.sorted.marked.bam"
# QC metrics for marked duplicates
dupe_metrics="${sample_id}_$genome_base.mark_dupes.metrics"

# Use temporary storage for computations
echo "rsync --progress $indir/$in_bam $TMPDIR/"
rsync --progress "$indir/$in_bam" "$TMPDIR/"

# Define memory for GATK4
# Allocate from remaining memory (/tmp stores in RAM)
file_mem="$(du -m "$TMPDIR/$in_bam" | awk '{print $1}')"
mem="$(( SLURM_MEM_PER_NODE - ( file_mem * 2 ) ))" # leave room for output BAM
# 75% of memory remaining
gatk_mem="$(( 75 * mem / 100 ))"
# Define memory per thread
mem_per_thread="$(( gatk_mem / SLURM_CPUS_PER_TASK ))M"
# Define number of threads for Spark
n_thread="$SLURM_CPUS_PER_TASK"
# n_thread="$(( SLURM_CPUS_PER_TASK - 1 ))"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's MarkDuplicates
cmd=(
  gatk
  --java-options "-Xms${gatk_mem}M -Xmx${gatk_mem}M"
  MarkDuplicatesSpark
  -R "$genome_local_unzip"
  --tmp-dir "$TMPDIR"
  -I "$TMPDIR/$in_bam"
  -O "$TMPDIR/$out_bam"
  -M "$TMPDIR/$dupe_metrics"
  # --VALIDATION_STRINGENCY LENIENT # for MarkDuplicates
  -VS LENIENT # for MarkDuplicatesSpark
  --spark-master "local[$n_thread]"
  --conf spark.local.dir="$TMPDIR"
  --conf spark.executor.cores="$n_thread"
  --conf spark.task.cpus=1
  --conf spark.executor.memory="$mem_per_thread"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Copy results from temporary storage
echo "rsync --progress $TMPDIR/$out_bam $outdir/"
rsync --progress "$TMPDIR/$out_bam" "$outdir/"
echo "rsync --progress $TMPDIR/$dupe_metrics $qc_dir/"
rsync --progress "$TMPDIR/$dupe_metrics" "$qc_dir/"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$out_bam" ]] && [[ -f "$qc_dir/$dupe_metrics" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - missing marked BAM ($out_bam) or QC ($dupe_metrics) for sample: $sample_id"
  echo "Checkpoint not created."
  exit 1
fi