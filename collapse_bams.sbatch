#!/bin/bash
#SBATCH -J collapse_bams
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --mem=50g
#SBATCH --time=5-0
#SBATCH --cpus-per-task=2

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

# Parse indiviual ID
indiv_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$indiv_list")"
# Output BAM named by individual ID
out_bam="$outdir/${indiv_id}_$genome_base.sorted.marked.merged.bam"

# Generate array of input BAM filenames associated with individual ID
mapfile -t input_bams < <(find "$indir" -type f -name "*_${indiv_id}_*.sorted.marked.bam")
# Add required "-I" flag before each filename
cnt=${#input_bams[@]}
for ((i=0;i<cnt;i++))
do
  input_bams[i]="-I ${input_bams[i]}"
done

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's MergeSamFiles
cmd=(
  gatk MergeSamFiles
  -R "$genome_local_unzip"
  "${input_bams[@]}"
  -O "$out_bam"
  --USE_THREADING
  --TMP_DIR "$tempdir"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$out_bam" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
  exit 0
else
  echo "Error - merged BAM file ($out_bam) not found."
  echo "Checkpoint not created."
  exit 1
fi

