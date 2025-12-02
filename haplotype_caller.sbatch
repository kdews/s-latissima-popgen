#!/bin/bash
#SBATCH -J haplotype_caller
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=10:00:00
#SBATCH --mem=5g
#SBTACH --cpus-per-task=12

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
indiv_list="$5" # list of individual IDs

# Create output directories (if needed)
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
# Input BAM
in_bam="${indiv_id}_$genome_base.sorted.marked.bam"
# Output gVCF file named from individual ID
out_gvcf="${indiv_id}_$genome_base.g.vcf.gz"

# Use temporary storage for computations
echo "rsync --progress $indir/$in_bam $TMPDIR/"
rsync --progress "$indir/$in_bam" "$TMPDIR/"

# Define memory for GATK4
# Allocate from remaining memory (/tmp stores in RAM)
tmp_mem="$(du -m "$TMPDIR" | awk '{print $1}')"
mem="$(( SLURM_MEM_PER_NODE - ( tmp_mem * 2 ) ))" # double for output file
# Minimum = 50% of memory remaining 
gatk_mem_min="$(( 5 * mem / 10 ))M"
# Maximum = 90% of memory remaining
gatk_mem_max="$(( 9 * mem / 10 ))M"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's HaplotypeCaller
cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  HaplotypeCaller
  -ERC GVCF
  -ploidy 1
  -R "$genome_local_unzip"
  --sequence-dictionary "$genome_dict"
  --tmp-dir "$TMPDIR"
  -I "$TMPDIR/$in_bam"
  -O "$TMPDIR/$out_gvcf"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Copy results from temporary storage
echo "rsync --progress $TMPDIR/$out_gvcf $TMPDIR/$out_gvcf.bai $outdir/"
rsync --progress "$TMPDIR/$out_gvcf" "$TMPDIR/$out_gvcf.bai" "$outdir/"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$out_gvcf" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - output gVCF file ($out_gvcf) not found."
  echo "Checkpoint not created."
  exit 1
fi

