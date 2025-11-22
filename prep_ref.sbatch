#!/bin/bash
#SBATCH -J prep_ref
#SBATCH -o %x.log
#SBATCH --time=02:00:00
#SBATCH --mem=500m

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

# Create sequence dictionary for downstream GATK tools
if [[ -f "$genome_dict" ]]
then
  echo "Detected GATK sequence dictionary: $genome_dict"
else
  # Load GATK4
  module purge
  module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
  gatk --version || exit 1
  # Build GATK4 sequence dictionary from uncompressed genome FASTA
  cmd=(
    gatk CreateSequenceDictionary
    -R "$genome_local_unzip"
    -O "$genome_dict"
  )
  echo "${cmd[*]}"
  "${cmd[@]}"
  unset cmd
  module purge
fi

# Create FASTA index with samtools
if [[ -f "$genome_idx" ]]
then
  echo "Detected FASTA index: $genome_idx"
else
  # Load conda
  cond=~/.conda_for_sbatch.sh
  if [[ -f "$cond" ]]
  then
    source "$cond"
  else
    echo "Error on source of $cond"
    exit 1
  fi
  # Load samtools
  conda activate samtools
  samtools --version || exit 1
  # Build samtools FASTA index from uncompressed genome FASTA
  cmd=(
    samtools faidx
    "$genome_local_unzip"
  )
  echo "${cmd[*]}"
  "${cmd[@]}"
fi

# Mark time at completion
echo; date; echo

# Checkpoint
mkdir -p checkpoints
if [[ -f "$genome_dict" ]]
then
  if [[ -f "$genome_idx" ]]
  then
    echo "Creating checkpoint."
    touch "checkpoints/$prefix.checkpoint"
    exit 0
  else
    echo "Error - genome index ($genome_idx) not found."
    echo "Checkpoint not created."
    exit 1
  fi
else
  echo "Error - dictionary ($genome_dict) not found."
  echo "Checkpoint not created."
  exit 1
fi

