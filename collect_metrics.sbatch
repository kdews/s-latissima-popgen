#!/bin/bash
#SBATCH -J collect_metrics
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=35g
#SBATCH --cpus-per-task=12

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
indiv_list="$5" # list of individual IDs

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

# Parse individual ID
indiv_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$indiv_list")"
# Input BAM file
uniq_id="${indiv_id}_$genome_base"
in_bam="$uniq_id.sorted.marked.bam"
# Input BAM index
in_bam_idx="$in_bam.bai"
# Verify input BAM & index exist in input directory
echo "Input alignment BAM: $indir/$in_bam"
echo "Input alignment BAM index: $indir/$in_bam_idx"
if [[ -f "$indir/$in_bam" ]] \
  && [[ -f "$indir/$in_bam_idx" ]]
then
  echo "Found input files in input directory: $indir"
else
  echo "Error - missing input BAM and/or index for $indiv_id"
  exit 1
fi
echo
# Output QC files named by program and ID
# CollectAlignmentSummaryMetrics
align_metrics="$uniq_id.alignment_summary_metrics.txt"
align_pdf="$uniq_id.read_length_histogram.pdf"
# CollectInsertSizeMetrics
insert_metrics="$uniq_id.insert_size_metrics.txt"
insert_pdf="$uniq_id.insert_size_histogram.pdf"
# CollectQualityYieldMetrics
qy_metrics="$uniq_id.quality_yield_metrics.txt"
# CollectWgsMetrics
wgs_metrics="$uniq_id.collect_wgs_metrics.txt"
# samtools stats
stats_file="$uniq_id.stats"

# Use temporary storage for computations
echo "rsync --progress $indir/$in_bam $indir/$in_bam_idx $TMPDIR/"
rsync --progress "$indir/$in_bam" "$indir/$in_bam_idx" "$TMPDIR/"

# Define memory for GATK4
# Allocate from remaining memory (/tmp stores in RAM)
tmp_mem="$(du -m "$TMPDIR" | awk '{print $1}')"
mem="$(( SLURM_MEM_PER_NODE - tmp_mem ))"
# Minimum = 50% of memory remaining 
gatk_mem_min="$(( 5 * mem / 10 ))M"
# Maximum = 90% of memory remaining
gatk_mem_max="$(( 9 * mem / 10 ))M"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35 r/4.4.3
gatk --version || exit 1
R --version || exit 1 # ensure R is loaded into env for CollectMultipleMetrics

# Run GATK4 CollectMultipleMetrics
mult_cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  CollectMultipleMetrics
  --MAX_RECORDS_IN_RAM 5000000
  -R "$genome_local_unzip"
  --TMP_DIR "$TMPDIR"
  --PROGRAM null
  --PROGRAM CollectAlignmentSummaryMetrics
  --PROGRAM CollectInsertSizeMetrics
  --PROGRAM CollectQualityYieldMetrics
  -EXT ".txt"
  -I "$TMPDIR/$in_bam"
  -O "$TMPDIR/$uniq_id" # output prefix
)
echo "${mult_cmd[*]}"
if "${mult_cmd[@]}"
then
  # Run GATK4's CollectWgsMetrics
  wgs_cmd=(
    gatk
    --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
    CollectWgsMetrics
    --USE_FAST_ALGORITHM
    --MAX_RECORDS_IN_RAM 5000000
    --READ_LENGTH 151 # give longest possible read length for fast algorithm
    -R "$genome_local_unzip"
    --TMP_DIR "$TMPDIR"
    -I "$TMPDIR/$in_bam"
    -O "$TMPDIR/$wgs_metrics"
  )
  echo "${wgs_cmd[*]}"
  if "${wgs_cmd[@]}"
  then
    # Unload GATK4 env
    module purge

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

    # Run samtools stats
    cmd=(
      samtools stats
      -@ "$SLURM_CPUS_PER_TASK"
      -r "$genome_local_unzip"
      "$TMPDIR/$in_bam"
    )
    echo "${cmd[*]} > $TMPDIR/$stats_file"
    if "${cmd[@]}" > "$TMPDIR/$stats_file"
    then
      check="pass"

      # Copy all resulting .txt, .stats, & .pdf files from temporary storage
      echo "rsync --progress $TMPDIR/${indiv_id}_$genome_base*.txt $outdir/"
      rsync --progress "$TMPDIR/${indiv_id}_$genome_base"*.txt "$outdir/"
      echo "rsync --progress $TMPDIR/$stats_file $outdir/"
      rsync --progress "$TMPDIR/$stats_file" "$outdir/"
      echo "rsync --progress $TMPDIR/${indiv_id}_$genome_base*.pdf $outdir/"
      rsync --progress "$TMPDIR/${indiv_id}_$genome_base"*.pdf "$outdir/"
    fi
  fi
fi

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] \
  && [[ -f "$outdir/$align_metrics" ]] \
  && [[ -f "$outdir/$align_pdf" ]] \
  && [[ -f "$outdir/$insert_metrics" ]] \
  && [[ -f "$outdir/$insert_pdf" ]] \
  && [[ -f "$outdir/$qy_metrics" ]] \
  && [[ -f "$outdir/$wgs_metrics" ]] \
  && [[ -f "$outdir/$stats_file" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - missing metrics QC files for BAM ($in_bam). Expected files:"
  echo "$outdir/$align_metrics"
  echo "$outdir/$align_pdf"
  echo "$outdir/$insert_metrics"
  echo "$outdir/$insert_pdf"
  echo "$outdir/$qy_metrics"
  echo "$outdir/$wgs_metrics"
  echo "$outdir/$stats_file"
  echo "Checkpoint not created."
  exit 1
fi
