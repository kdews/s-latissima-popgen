#!/bin/bash
#SBATCH --mem=40gb
#SBATCH --time=1-0
#SBATCH --cpus-per-task=12

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
genome="$4" # genome FASTA

# Create output directory (if needed)
mkdir -p "$outdir"

# Parse genome filename
genome_basename="$(basename "$genome")"
genome_basename_unzip="${genome_basename%%.gz}"
genome_base="${genome_basename%%.*}"
# HISAT2 index file prefix
ht2_idx="$outdir/$genome_base"

# Copy input genome file to $outdir (if needed)
if [[ ! -f "$outdir/$genome_basename" ]]
then
    echo "Copying genome ($genome) to: $(realpath -e "$outdir")."
    rsync -avc "$genome" "$outdir/"
fi
# Unzip copied genome (if needed)
if [[ ! -f "$outdir/$genome_basename_unzip" ]]
then
    module purge
    module load ver/2506 gcc/14.3.0 gzip/1.14
    echo "Unzipping genome: $outdir/$genome_basename"
    gunzip "$outdir/$genome_basename"
    module purge
fi

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -a "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load HISAT2
conda activate hisat2
hisat2-build --version

# Start HISAT2-build run
echo "Running HISAT2-build on genome file: $genome_basename_unzip"
cmd=(
    hisat2-build
    -p "$SLURM_CPUS_PER_TASK"
    "$genome_basename_unzip"
    "$ht2_idx"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoint
mkdir -p checkpoints
if (( $(find "$outdir" -type f -name "$genome_base.*.ht2" | wc -l) > 0 ))
then    
    echo "Creating checkpoint."
    touch "checkpoints/$prefix.checkpoint"
    exit 0
else
    echo "Error - HISAT2 index files ($ht2_idx.*.ht2) not detected."
    echo "Checkpoint not created."
    exit 1
fi

