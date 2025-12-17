#!/bin/bash
#SBATCH -J bcftools_concat
#SBATCH -o %x.log
#SBATCH --time=4-0
#SBATCH --mem=100g
#SBATCH --cpus-per-task=11

# Log Slurm job details
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
vcf_list="$5" # list of genotyped VCF files

# Source genome config
if [[ -f "$genome_config" ]]
then
  source "$genome_config"
else
  echo "Error on source of genome config: $genome_config"
  exit 1
fi

# Output VCF named from genome FASTA
out_vcf="$outdir/master_$genome_base.vcf.gz"

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load bcftools
conda activate bcftools
bcftools --version || exit 1

# Define threads for bcftools
n_thread="$(( SLURM_CPUS_PER_TASK - 1 ))"

# Run bcftools concat
cmd=(
  bcftools concat
  -f "$vcf_list" # list of VCF filenames
  --threads "$n_thread"
  -W "tbi" # create TBI index of compressed output VCF
  -o "$out_vcf"
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
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - VCF file ($out_vcf) not found."
  echo "Checkpoint not created."
  exit 1
fi
