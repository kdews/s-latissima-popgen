#!/bin/bash
#SBATCH -J genotype_gvcfs
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=04:00:00
#SBATCH --mem=17g

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
indir="$3" # parent input directory containing subdirectories
outdir="$4" # output directory
intervals_list="$5" # text file listing interval filenames

# Name temp directory after job name
tempdir="${prefix}_tmp"

# Create output and temp directories (if needed)
mkdir -p "$outdir"
mkdir -p "$tempdir"

# Subdirectory for this job step
indir="$indir/interval_$SLURM_ARRAY_TASK_ID"

# Source genome config
if [[ -f "$genome_config" ]]
then
  source "$genome_config"
else
  echo "Error on source of genome config: $genome_config"
  exit 1
fi

# Parse interval
interval="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$intervals_list")"
# Output VCF named based on interval
out_vcf="$outdir/interval_${SLURM_ARRAY_TASK_ID}_$genome_base.vcf.gz"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's GenotypeGVCFs with GenomicsDBImport option
cmd=(
  gatk
  --java-options "-Xms14g -Xmx14g"
  GenotypeGVCFs
  -R "$genome_local_unzip"
  --sequence-dictionary "$genome_dict"
  -L "$interval"
  -V "gendb://$indir"
  -O "$out_vcf"
  --tmp-dir "$tempdir"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$out_vcf" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - output VCF file ($out_vcf) not found."
  echo "Checkpoint not created."
  exit 1
fi
