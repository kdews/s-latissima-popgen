#!/bin/bash
#SBATCH -J bcftools_concat
#SBATCH -o %x.log
#SBATCH --time=05:00:00
#SBATCH --mem=15g
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
vcf_list="$5" # list of genotyped VCF files

# Source genome config
if [[ -f "$genome_config" ]]
then
  source "$genome_config"
else
  echo "Error on source of genome config: $genome_config"
  exit 1
fi

# Check input VCF files exist
mapfile -t vcfs < "$vcf_list"
for vcf in "${vcfs[@]}"
do
  if ! [[ -f "$vcf" ]]
  then
    echo "Error - input VCF ($vcf) not found. Check VCF list: $vcf_list"
    exit 1
  fi
done
# Output VCF named from genome FASTA
out_vcf="$outdir/master_2025_$genome_base.vcf.gz"

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

# Run bcftools concat
cmd=(
  bcftools concat
  --threads "$SLURM_CPUS_PER_TASK"
  -f "$vcf_list" # list of input VCF file paths
  -O z
  -o "$out_vcf"
)
echo "${cmd[*]}"
if "${cmd[@]}"
then
  # Index full VCF file
  cmd2=(
    bcftools index
    --threads "$SLURM_CPUS_PER_TASK"
    --tbi
    "$out_vcf"
  )
  echo
  echo "${cmd2[*]}"
  "${cmd2[@]}" && check="pass"
fi

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] && [[ -f "$out_vcf" ]] && [[ -f "$out_vcf.tbi" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - VCF file ($out_vcf) or index ($out_vcf.tbi) not found."
  echo "Checkpoint not created."
  exit 1
fi
