#!/bin/bash
#SBATCH --mem=1g
#SBATCH --time=01:00:00

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
genome_config="$4" # genome config file
intervals_list="$5"
scatter="$6" # integer; target number of interval_lists to split into

# Source genome config
if [[ -f "$genome_config" ]]
then
    source "$genome_config"
else
    echo "Error on source of genome config: $genome_config"
    exit 1
fi

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version

# Run GATK4's SplitIntervals
cmd=(
    gatk SplitIntervals
    -R "$genome_local_unzip"
    --sequence-dictionary "$genome_dict"
    -O "$outdir"
    --scatter-count "$scatter"
    --subdivision-mode BALANCING_WITHOUT_INTERVAL_SUBDIVISION
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoint
mkdir -p checkpoints
mapfile -t seqids < <(cut -f1 "$genome_idx")
n_seq="$(wc -l < "$genome_idx")"
n_seq_split="$(find "$outdir" -type f -exec grep -v "@" {} + | \
    grep -E -c "$(IFS='|'; echo "${seqids[*]}")")"
if [[ "$n_seq" -eq "$n_seq_split" ]]
then
    # Create list of interval filenames
    find "$outdir" -type f -name "*.list" > "$intervals_list"
    echo "Creating checkpoint."
    touch "checkpoints/$prefix.checkpoint"
    exit 0
else
    echo "Error - not all chromosomes found in split interval lists in $outdir"
    echo "Checkpoint not created."
    exit 1
fi

