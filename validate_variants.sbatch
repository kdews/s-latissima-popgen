#!/bin/bash
#SBATCH -J validate_variants
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=05:00:00
#SBATCH --mem=8g

# Log Slurm job details
echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
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
id_file="$5" # index file (any text file list in indexer/)
pattern="$6" # SAM/BAM file ending pattern (e.g., .sorted.bam)

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

# Parse ID from index file
if [[ "$id_file" == "indexer/intervals_list.txt" ]]
then
  # Use Slurm ID for genomic intervals
  id="interval_${SLURM_ARRAY_TASK_ID}"
else
  id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$id_file")"
fi
# Input VCF file
in_vcf="${id}_${genome_base}${pattern}"
# Input VCF index
in_vcf_idx="${id}_${genome_base}${pattern}.tbi"
# Verify input BAM & index exist in input directory
echo "Input alignment VCF: $indir/$in_vcf"
echo "Input alignment VCF index: $indir/$in_vcf_idx"
if [[ -f "$indir/$in_vcf" ]] \
  && [[ -f "$indir/$in_vcf_idx" ]]
then
  echo "Found input files in input directory: $indir"
else
  echo "Error - missing input VCF and/or index for $id"
  exit 1
fi
echo
# Output QC summary file named from ID
out_summary="$in_vcf.validate.summary"

# Use temporary storage for computations
echo "rsync --progress $indir/$in_vcf $indir/$in_vcf_idx $TMPDIR/"
rsync --progress "$indir/$in_vcf" "$indir/$in_vcf_idx" "$TMPDIR/"

# Define memory for GATK4
# Allocate from remaining memory (/tmp stores in RAM)
tmp_mem="$(du -m "$TMPDIR" | awk '{print $1}')"
mem="$(( SLURM_MEM_PER_NODE - tmp_mem ))"
# Minimum = 50% of memory remaining 
gatk_mem_min="$(( 5 * mem / 10 ))M"
# Maximum = 90% of memory remaining
gatk_mem_max="$(( 9 * mem / 10 ))M"

# Set $filetype_flag to -gvcf, if needed
if echo "$in_vcf" | grep -Pq "\.g\.vcf|gvcf"
then
  echo "Treating input file ($in_vcf) as gVCF file."
  filetype_flag="-gvcf"
else
  echo "Treating input file ($in_vcf) as VCF file."
fi 

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's ValidateVariants
cmd=(
  gatk ValidateVariants
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  "$filetype_flag"
  --validation-type-to-exclude ALLELES
  -R "$genome_local_unzip"
  --sequence-dictionary "$genome_dict"
  -V "$TMPDIR/$in_vcf"
)
echo "${cmd[*]} > $TMPDIR/$out_summary 2>&1"
"${cmd[@]}" > "$TMPDIR/$out_summary" 2>&1

# Copy result from temporary storage
echo "rsync --progress $TMPDIR/$out_summary $outdir/"
rsync --progress "$TMPDIR/$out_summary" "$outdir/"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$out_summary" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - ValidateVariant summary for input file ($in_vcf) not found."
  echo "Checkpoint not created."
  exit 1
fi
