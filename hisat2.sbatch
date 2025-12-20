#!/bin/bash
#SBATCH -J hisat2
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=02:00:00
#SBATCH --mem=145g
#SBATCH --cpus-per-task=16

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
indiv_list="$7" # file to write parsed individual IDs

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

# Parse sample ID and trimmed read filenames
sample_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$samples_list")"
reads1="$indir/${sample_id}_R1_val_1.fq.gz"
reads2="$indir/${sample_id}_R2_val_2.fq.gz"
# Verify read files exist
if [[ -f "$reads1" ]] && [[ -f "$reads2" ]]
then
  echo "Parsing read groups from sample ID ($sample_id) and associated read files:"
  echo "1: $reads1"
  echo "2: $reads2"
else
  echo "Error - missing input file for $sample_id"
  exit 1
fi
# Create ID for BAM files
bam_id="${sample_id}_$genome_base"
# Temporary BAM filename before GATK4 fixes
tmp1_bam="$bam_id.sorted.pre.bam"
# Temporary BAM filename after GATK4 FixMateInformation
tmp2_bam="$bam_id.sorted.fm.bam"
# Output final sorted BAM with GATK4 read mate & NM tag fixes
out_bam="$bam_id.sorted.bam"
# Output QC summary file named from BAM ID
out_summary="$qc_dir/$bam_id.hisat2.summary"

# Define threads for each command
hisat_thr="$(( 3 * SLURM_CPUS_PER_TASK / 4 ))"
samtools_thr="$(( 1 * SLURM_CPUS_PER_TASK / 4 ))"
# Define memory per thread for samtools sort (90% of total to avoid OOM error)
mem_per_thread="$(( 9 * SLURM_MEM_PER_NODE / SLURM_CPUS_PER_TASK / 10 ))M"

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load HISAT2 (env includes samtools)
conda activate hisat2
hisat2 --version || exit 1
samtools --version || exit 1

# Define read groups for SAM headers from sample ID and FASTQ file read IDs
# Input sample ID format = SampleID_Library_RunID_Barcode_Plate_Lane_Read
# Create array 'rgs1' from sample ID by splitting on '_'
IFS='_' read -r -a rgs1 <<< "$sample_id"
# Read first line of FASTQ to get read ID
read_id="$(zcat "$reads1" | head -n1 | awk '{print $1}' | sed 's/@//g')"
# Create array 'rgs2' from read ID by splitting on ':'
IFS=':' read -r -a rgs2 <<< "$read_id"
# Index rgs1 (sample ID array) and rgs2 (read ID array) to generate read group values
# Read group ID = {FLOWCELL_BARCODE}.{LANE}
rg_id="${rgs2[2]}.${rgs2[3]}"
echo "Read group ID = ID:$rg_id"
# Read group SaMple name (SM) = shortened SampleID within input sample ID (no UniqueID)
rg_sm="${rgs1[0]}"
echo "Read group sample name = SM:$rg_sm"
# Save parsed individual ID to index file
echo "$rg_sm" >> "$indiv_list"
# Read group Platform Unit (PU) = {FLOWCELL_BARCODE}.{LANE}.{SAMPLE_NAME}
rg_pu="${rgs2[2]}.${rgs2[3]}.${rgs1[0]}"
echo "Read group platform unit = PU:$rg_pu"
# Read group LiBrary identifier = SampleID-UniqueID
rg_lb="${rgs1[0]}-${rgs1[1]}"
echo "Read group library identifier = LB:$rg_lb"
# Read group PLatform (PL) = ILLUMINA
rg_pl="ILLUMINA"
echo "Read group platform = PL:$rg_pl"

# Run HISAT2 alignment
echo
echo "Running HISAT2 on read files associated with sample ID: $sample_id"
echo "1: $reads1" 
echo "2: $reads2"
hisat2_cmd=(
  hisat2
  -p "$hisat_thr"
  --time
  -x "$ht2_idx"
  -1 "$reads1"
  -2 "$reads2"
  --rg-id "$rg_id"
  --rg "SM:$rg_sm"
  --rg "LB:$rg_lb"
  --rg "PU:$rg_pu"
  --rg "PL:$rg_pl"
  --new-summary
  --summary-file "$out_summary"
)
# Sort by coordinate (default) and convert SAM to BAM
samtools_cmd=(
  samtools sort
  -@ "$samtools_thr"
  -m "$mem_per_thread"
  -O bam
  -o "$TMPDIR/$tmp1_bam"
)
echo "${hisat2_cmd[*]} | ${samtools_cmd[*]}"
set -o pipefail
if "${hisat2_cmd[@]}" | "${samtools_cmd[@]}"
then
  # Define memory for GATK4 FixMateInformation
  # Allocate from remaining memory (/tmp stores in RAM)
  file_mem="$(du -m "$TMPDIR/$tmp1_bam" | awk '{print $1}')"
  mem="$(( SLURM_MEM_PER_NODE - file_mem ))"
  # Minimum = 50% of memory remaining 
  gatk_mem_min="$(( 5 * mem / 10 ))M"
  # Maximum = 90% of memory remaining
  gatk_mem_max="$(( 9 * mem / 10 ))M"

  # Load GATK4
  module purge
  module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
  gatk --version || exit 1

  # Fix read mate pairs with GATK4
  # HISAT2 incorrectly doesn't set 0x20 for unmapped reads with reverse-mapped mate
  fixmate_cmd=(
    gatk
    --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
    FixMateInformation
    --MAX_RECORDS_IN_RAM 5000000
    -R "$genome_local_unzip"
    --TMP_DIR "$TMPDIR"
    -I "$TMPDIR/$tmp1_bam"
    -O "$TMPDIR/$tmp2_bam"
  )
  echo "${fixmate_cmd[*]}"
  if "${fixmate_cmd[@]}"
  then
    # Define memory for GATK4 SetNmMdAndUqTags
    # Allocate from remaining memory (/tmp stores in RAM)
    file_mem2="$(du -m "$TMPDIR/$tmp2_bam" | awk '{print $1}')"
    mem="$(( SLURM_MEM_PER_NODE - file_mem - file_mem2 ))"
    # Minimum = 50% of memory remaining 
    gatk_mem_min="$(( 5 * mem / 10 ))M"
    # Maximum = 90% of memory remaining
    gatk_mem_max="$(( 9 * mem / 10 ))M"

    # Recalculate NM tags with GATK4
    set_nm_cmd=(
      gatk
      --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
      SetNmMdAndUqTags
      --MAX_RECORDS_IN_RAM 5000000
      -R "$genome_local_unzip"
      --TMP_DIR "$TMPDIR"
      -I "$TMPDIR/$tmp2_bam"
      -O "$TMPDIR/$out_bam"
    )
    echo "${set_nm_cmd[*]}"
    if "${set_nm_cmd[@]}"
    then
      # Index final coordinate-sorted BAM
      samtools_cmd_2=(
        samtools index
        -@ "$SLURM_CPUS_PER_TASK"
        --bai
        "$TMPDIR/$out_bam"
      )
      echo "${samtools_cmd_2[*]}"
      if "${samtools_cmd_2[@]}"
      then
        check="pass"
        # Copy only final BAM to working directory
        echo "rsync --progress $TMPDIR/$out_bam $TMPDIR/$out_bam.bai $outdir/"
        rsync --progress "$TMPDIR/$out_bam" "$TMPDIR/$out_bam.bai" "$outdir/"
      fi
    fi
  fi
fi

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] \
  && [[ -f "$outdir/$out_bam" ]] \
  && [[ -f "$outdir/$out_bam.bai" ]] \
  && [[ -f "$out_summary" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - alignment not completed for sample ID: $sample_id"
  echo "Checkpoint not created."
  exit 1
fi
