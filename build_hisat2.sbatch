#!/bin/bash
#SBATCH --mem=40gb
#SBATCH --time=1-0
#SBATCH --cpus-per-task=12

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
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

# Copy and uncompress input genome file to $indir (if needed)
if [[ ! -f "$genome_local_unzip" ]]
then
    if [[ ! -f "$genome_local" ]]
    then
        echo "Copying genome ($genome) to: $(realpath -e "$indir")"
        rsync -avc "$genome" "$indir/"
    fi
    module purge
    module load ver/2506 gcc/14.3.0 gzip/1.14
    echo "Unzipping genome: $genome_local"
    gunzip "$genome_local"
    module purge
fi

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
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
echo "Running HISAT2-build on genome file: $genome_local_unzip"
cmd=(
    hisat2-build
    -p "$SLURM_CPUS_PER_TASK"
    "$genome_local_unzip"
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

