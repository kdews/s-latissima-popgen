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


# GATK4 Spark parameters
# Define number of threads (cores)
n_thread="$SLURM_CPUS_PER_TASK"
# Allocate from remaining memory (/tmp stores in RAM)
file_mem="$(du -m "$TMPDIR/$in_bam" | awk '{print $1}')" # force unit=M
mem="$(( SLURM_MEM_PER_NODE - ( file_mem * 2 ) ))" # double for output file
# Save 4gb for driver/off-heap and other threads
driver_mem=4000 # unit=M
exec_mem="$(( mem - driver_mem ))" # unit=M
mem_per_thread="$(( exec_mem / n_thread ))" # unit=M
offheap_mem=2000 # off-heap shuffle buffer (unit=M)
# Partitons used for shuffling data during joins/aggregations
shuffle_parts="$(( n_thread * 3 ))" # avoid default 200

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's MarkDuplicates
cmd=(
  gatk
  # --java-options "-Xms${gatk_mem}M -Xmx${gatk_mem}M"
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
  --conf spark.task.cpus=1
  --conf spark.executor.cores="$n_thread"
  --conf spark.driver.cores=1
  # --conf spark.executor.memory="${mem_per_thread}M"
  --conf spark.executor.memory="${exec_mem}M"
  --conf spark.driver.memory="${driver_mem}M"
  --conf spark.memory.offHeap.enabled=true
  --conf spark.memory.offHeap.size="${offheap_mem}M"
  --conf spark.sql.shuffle.partitions="$shuffle_parts"
  --conf spark.shuffle.file.buffer=32k
  --conf spark.executor.heartbeatInterval="60s"
  --conf spark.network.timeout="300s"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Copy results from temporary storage
echo "rsync --progress $TMPDIR/$out_bam $TMPDIR/$out_bam.bai $outdir/"
rsync --progress "$TMPDIR/$out_bam" "$TMPDIR/$out_bam.bai" "$outdir/"
echo "rsync --progress $TMPDIR/$dupe_metrics $qc_dir/"
rsync --progress "$TMPDIR/$dupe_metrics" "$qc_dir/"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$out_bam" ]] \
  && [[ -f "$outdir/$out_bam.bai" ]] \
  && [[ -f "$qc_dir/$dupe_metrics" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - missing one of three expected output files for sample $sample_id:"
  echo "Duplicate marked BAM ($out_bam)"
  echo "BAM index ($out_bam.bai)"
  echo "QC file ($dupe_metrics)"
  echo "Checkpoint not created."
  exit 1
fi