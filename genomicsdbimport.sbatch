#!/bin/bash
#SBATCH -J genomicsdbimport
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=1-0
#SBATCH --mem=50g

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
outdir="$4" # parent output directory containing subdirectories
intervals_list="$5" # text file listing interval filenames
gvcf_list="$6" # list of gVCF filenames

# Create parent output and temp directories (if needed)
mkdir -p "$outdir"

# Subdirectory for this job step
outdir="$outdir/interval_$SLURM_ARRAY_TASK_ID"

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

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

## Generate array to hold list all g.vcfs
## and the required "-V" flag before each
#f=`ls ${indir}/*.g.vcf.gz`
#input_gvcfs=(${f// / })
#cnt=${#input_gvcfs[@]}
#for ((i=0;i<cnt;i++)); do
#  input_gvcfs[i]="-V ${input_gvcfs[i]}"
#done

# Define memory for GATK4
# Minimum = 50% of memory
gatk_mem_min="$(( 5 * SLURM_MEM_PER_NODE / 10 ))M"
# Maximum = 90% of memory
gatk_mem_max="$(( 9 * SLURM_MEM_PER_NODE / 10 ))M"

# Run GATK4's GenomicsDBImport
cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  # --java-options "-Xms39g -Xmx39g"
  GenomicsDBImport
  -R "$genome_local_unzip"
  --sequence-dictionary "$genome_dict"
  -L "$interval"
  # -V "$gvcf_list"
  --sample-name-map "$gvcf_list"
  --genomicsdb-workspace-path "$outdir"
  # Give TMPDIR environment variable (Slurm sets this)
  --tmp-dir "$TMPDIR"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
if [[ -d "$outdir" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - output Genomics Database Workspace ($outdir) not found."
  echo "Checkpoint not created."
  exit 1
fi

