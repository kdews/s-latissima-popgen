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
infile_list="$5" # list of input variant files

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

# Parse input filename
infile="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$infile_list")"
infile_basename="$(basename "$infile")"
# Output QC summary
out_summary="$outdir/$infile_basename.validate.summary"

# Set $filetype_flag to -gvcf, if needed
if echo "$infile" | grep -Pq "g\.vcf|gvcf"
then
  echo "Treating input file ($infile) as gVCF file."
  filetype_flag="-gvcf"
else
  echo "Treating input file ($infile) as VCF file."
fi 

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's ValidateVariants
cmd=(
  gatk ValidateVariants
  "$filetype_flag"
  --validation-type-to-exclude ALLELES
  -R "$genome_local_unzip"
  -V "$infile"
)
echo "${cmd[*]} > $out_summary 2>&1"
"${cmd[@]}" > "$out_summary" 2>&1

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$out_summary" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - ValidateVariant summary for input file ($infile) not found."
  echo "Checkpoint not created."
  exit 1
fi
