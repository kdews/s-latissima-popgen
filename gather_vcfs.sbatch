#!/bin/bash
#SBATCH -J gather_vcfs
#SBATCH -o %x.log
#SBATCH --time=1-0
#SBATCH --mem=30g

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

# Output VCF named from genome FASTA
out_vcf="$outdir/master_$genome_base.vcf.gz"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Define memory for GATK4
# Minimum = 50% of memory
gatk_mem_min="$(( 5 * SLURM_MEM_PER_NODE / 10 ))M"
# Maximum = 90% of memory
gatk_mem_max="$(( 9 * SLURM_MEM_PER_NODE / 10 ))M"

# Run GATK4's GatherVcfs
cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  GatherVcfs
  --MAX_RECORDS_IN_RAM 5000000
  -R "$genome_local_unzip"
  -D "$genome_dict"
  -I "$vcf_list" # list of VCF filenames (.list file)
  -O "$out_vcf"
  # Give TMPDIR environment variable (Slurm sets this)
  --TMP_DIR "$TMPDIR"
)
echo "${cmd[*]}"
"${cmd[@]}" && check="pass"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ "$check" == "pass" ]] && [[ -f "$out_vcf" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - VCF file ($out_vcf) not found."
  echo "Checkpoint not created."
  exit 1
fi
