#!/bin/bash
#SBATCH -J bcftools_stats
#SBATCH -o %x.log
#SBATCH --time=05:00:00
#SBATCH --mem=100g

# Log Slurm job details
echo "Partition: $SLURM_JOB_PARTITION"

# Print date and time
date
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory

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

# Input VCF file
in_vcf="master_$genome_base.vcf.gz"
# Verify input file exists
[[ -f "$in_vcf" ]] \
  || { echo "Error - missing input VCF file ($in_vcf)"; exit 1; }
# Output evaluation QC file
stats_file="master_$genome_base.bcftools.stats"

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

# Run bcftools stats
cmd=(
  bcftools stats
  -s
  "$in_vcf"
)
echo "${cmd[*]} > $outdir/$stats_file"
"${cmd[@]}" > "$outdir/$stats_file"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$stats_file" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - missing variant eval file ($stats_file) for VCF ($in_vcf)."
  echo "Checkpoint not created."
  exit 1
fi
