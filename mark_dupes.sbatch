#!/bin/bash
#SBATCH -J mark_dupes
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=02:00:00
#SBATCH --mem=65g
#SBATCH --cpus-per-task=8

# Print date and time
date_fmt="%-I:%M:%S %p (%a %d %b %Y)" # date format
date +"$date_fmt"
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
indiv_list="$5" # list of individual IDs
qc_dir="$6" # directory to write QC output

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
fi
echo "Partition: $SLURM_JOB_PARTITION"

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

# Parse indiviual ID
indiv_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$indiv_list")"
echo "Individual ID: $indiv_id"
# Generate array of input BAM filenames associated with individual ID
mapfile -t input_bams < <(find "$indir" -type f -name "${indiv_id}_*.sorted.bam")
echo "Input BAM file(s):"
echo "${input_bams[*]}"
echo
# Output marked BAM file
out_bam="${indiv_id}_$genome_base.sorted.marked.bam"
# QC metrics for marked duplicates
metrics_file="${indiv_id}_$genome_base.marked_dup_metrics.txt"

# Define number of threads (cores)
n_thread="$SLURM_CPUS_PER_TASK"

# Copy input files to temporary storage for computations
cnt=${#input_bams[@]}
bam_args=()
for (( i=0; i<cnt; i++ ))
do
  # Verify each input file exists
  in_bam="$(basename "${input_bams[i]}")"
  if [[ -f "$indir/$in_bam" ]]
  then
    if (( cnt > 1 ))
    then
      # Sort by queryname into /tmp if multiple input BAM files
      q_bam="${in_bam%%.sorted.bam}.queryname.bam"
      # Load conda
      cond=~/.conda_for_sbatch.sh
      if [[ -f "$cond" ]]
      then
        source "$cond"
      else
        echo "Error on source of $cond"
        exit 1
      fi
      # Load samtools
      conda activate samtools
      samtools --version || exit 1
      # Allocate from remaining memory (/tmp stores in RAM)
      file_mem="$(du -m "$indir/$in_bam" | awk '{print $1}')" # unit=M
      tmp_mem="$(du -m "$TMPDIR" | awk '{print $1}')" # unit=M
      mem="$(( SLURM_MEM_PER_NODE - file_mem - tmp_mem ))" # unit=M
      # Memory per thread for samtools sort (90% of total to avoid OOM error)
      mem_per_thread="$(( 9 * mem / n_thread / 10 ))" # unit=M
      # Sort by queryname using samtools
      samtools_cmd=(
        samtools sort
        -n
        -@ "$n_thread"
        -m "${mem_per_thread}M"
        -O bam
        -o "$TMPDIR/$q_bam"
        "$indir/$in_bam"
      )
      echo "${samtools_cmd[*]}"
      if "${samtools_cmd[@]}" && [[ -f "$TMPDIR/$q_bam" ]]
      then
        in_bam="$q_bam"
      else
        echo "Error - queryname sorted BAM ($q_bam) not created."
        exit 1
      fi
      conda deactivate
    else
      # Otherwise copy input BAM to /tmp
      echo "rsync --progress $indir/$in_bam $TMPDIR/"
      rsync --progress "$indir/$in_bam" "$TMPDIR/"
    fi
    # Save updated file path and add required "-I" flag before each filename
    # input_bams[i]="$TMPDIR/$in_bam"
    bam_args+=("-I" "$TMPDIR/$in_bam")
  else
    echo "Error - missing input file ($in_bam) for ID: $indiv_id"
    exit 1
  fi
done

# GATK4 Spark parameters
# Allocate from remaining memory (/tmp stores in RAM)
tmp_mem="$(du -m "$TMPDIR" | awk '{print $1}')" # force unit=M
mem="$(( SLURM_MEM_PER_NODE - ( tmp_mem * 2 ) ))" # double for output file
# Save 4gb for driver/off-heap and other threads
driver_mem=4000 # unit=M
exec_mem="$(( mem - driver_mem ))" # unit=M
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
  MarkDuplicatesSpark
  -R "$genome_local_unzip"
  --tmp-dir "$TMPDIR"
  "${bam_args[@]}"
  -O "$TMPDIR/$out_bam"
  -M "$TMPDIR/$metrics_file"
  # --VALIDATION_STRINGENCY LENIENT # for MarkDuplicates
  -VS LENIENT # for MarkDuplicatesSpark
  --spark-master "local[$n_thread]"
  --conf spark.local.dir="$TMPDIR"
  --conf spark.task.cpus=1
  --conf spark.executor.cores="$n_thread"
  --conf spark.driver.cores=1
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
"${cmd[@]}" && check="pass"

# Copy results from temporary storage
echo "rsync --progress $TMPDIR/$out_bam $TMPDIR/$out_bam.bai $outdir/"
rsync --progress "$TMPDIR/$out_bam" "$TMPDIR/$out_bam.bai" "$outdir/"
echo "rsync --progress $TMPDIR/$metrics_file $qc_dir/"
rsync --progress "$TMPDIR/$metrics_file" "$qc_dir/"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] \
  && [[ -f "$outdir/$out_bam" ]] \
  && [[ -f "$outdir/$out_bam.bai" ]] \
  && [[ -f "$qc_dir/$metrics_file" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - missing one of three expected output files for sample $indiv_id:"
  echo "Duplicate marked BAM ($out_bam)"
  echo "BAM index ($out_bam.bai)"
  echo "QC file ($metrics_file)"
  echo "Checkpoint not created."
  exit 1
fi