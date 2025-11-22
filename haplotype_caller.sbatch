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
date
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
indiv_list="$5" # list of individual IDs

# Name temp directory after job name
tempdir="${prefix}_tmp"

# Create output and temp directories (if needed)
mkdir -p "$outdir"
mkdir -p "$tempdir"

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
in_bam="$indir/${indiv_id}_$genome_base.sorted.marked.merged.bam"
# Output gVCF file named from individual ID
out_gvcf="$outdir/${indiv_id}_$genome_base.g.vcf.gz"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's HaplotypeCaller
cmd=(
  gatk
  # --java-options "-Xms4g -Xmx4g"
  HaplotypeCaller
  -ERC GVCF
  -ploidy 1
  -R "$genome_local_unzip"
  --sequence-dictionary "$genome_dict"
  -I "$in_bam"
  -O "$out_gvcf"
  --tmp-dir "$tempdir"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$out_gvcf" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - output gVCF file ($out_gvcf) not found."
  echo "Checkpoint not created."
  exit 1
fi

