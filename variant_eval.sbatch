#!/bin/bash
#SBATCH -J variant_eval
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
eval_file="master_$genome_base.variant_eval.txt"

# Define memory for GATK4
# Minimum = 50% of memory 
gatk_mem_min="$(( 5 * SLURM_MEM_PER_NODE / 10 ))M"
# Maximum = 90% of memory
gatk_mem_max="$(( 9 * SLURM_MEM_PER_NODE / 10 ))M"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's VariantEval
cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  VariantEval
  -R "$genome_local_unzip"
  --sequence-dictionary "$genome_dict"
  --tmp-dir "$TMPDIR"
  --eval "$in_vcf"
  -O "$outdir/$eval_file"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$outdir/$eval_file" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - missing variant eval file ($eval_file) for VCF ($in_vcf)."
  echo "Checkpoint not created."
  exit 1
fi
