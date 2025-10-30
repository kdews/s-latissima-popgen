#!/bin/bash
#SBATCH --mem=15gb
#SBATCH --time=01:00:00

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
scripts_dir="$5" # optional: directory containing scripts (MUST end in '/')

# MultiQC config file
multiqc_config="multiqc_config.yaml"
# If $scripts_dir exists, prepend path to config
if [[ -d "$scripts_dir" ]]
then
    multiqc_config="${scripts_dir}${multiqc_config}"
fi

# Verify input directory exists
if [[ -d "$indir" ]]
then
    echo "Running MultiQC on: $indir"
else
    echo "Error - input directory to MultiQC ($indir), not found."
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

# Load multiqc
conda activate multiqc
multiqc --version

# Run MultiQC
cmd=(
    multiqc
    -c "$multiqc_config"
    -o "$outdir"
    "$indir"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoints
mkdir -p checkpoints
if [[ -f ${qc_dir}/multiqc_report.html  ]]
then
    echo "Creating checkpoint."
    touch "checkpoints/$prefix.checkpoint"
    exit 0
else
    echo "Error - MultiQC report not created."
    echo "Checkpoint not created."
    exit 1
fi

