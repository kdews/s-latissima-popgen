#!/bin/bash
#SBATCH --mem=1g
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=5

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
genome="$4" # genome FASTA
indiv_list="$5" # list of individual IDs

# Parse genome filename
genome_basename="$(basename "$genome")"
genome_base="${genome_basename%%.*}"
# Parse individual ID
indiv_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$indiv_list")"
in_bam="$indir/${indiv_id}_$genome_base.sorted.marked.merged.bam"

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -a "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load samtools
conda activate samtools
samtools --version

# Index BAM with samtools
cmd=(
	samtools index
	-@ "$SLURM_CPUS_PER_TASK"
	"$in_bam"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoint
mkdir -p checkpoints
if [[ -f "$in_bam.bai" ]]
then
	echo "Creating checkpoint."
	touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
	exit 0
else
	echo "Error - no BAM index ($in_bam.bai) found."
	echo "Checkpoint not created."
	exit 1
fi
