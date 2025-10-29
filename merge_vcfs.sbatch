#!/bin/bash
#SBATCH --mem=100g
#SBATCH --time=4-0

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
genome_config="$4" # genome config file
vcf_list="$5" # list of genotyped VCF files

# Name temp directory after job name
tempdir="${prefix}_tmp"

# Create temp directory (if needed)
mkdir -p "$tempdir"

# Source genome config
if [[ -f "$genome_config" ]]
then
    source "$genome_config"
else
    echo "Error on source of genome config: $genome_config"
    exit 1
fi

# Output VCF named from genome FASTA
out_vcf="master_$genome_base.vcf.gz"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version

# Run GATK4's MergeVcfs
cmd=(
    gatk MergeVcfs
    --java-options "-Xms85g -Xmx85g"
    -R "$genome_local_unzip"
    -D "$genome_dict"
    -I "$vcf_list"
    -O "$out_vcf"
    --TMP_DIR "$tempdir"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoint
mkdir -p checkpoints
if [[ -f "$out_vcf" ]]
then
    echo "Creating checkpoint."
    touch "checkpoints/$prefix.checkpoint"
    exit 0
else
    echo "Error - VCF file ($out_vcf) not found."
    echo "Checkpoint not created."
    exit 1
fi
