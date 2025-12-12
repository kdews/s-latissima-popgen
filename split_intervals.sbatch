#!/bin/bash
#SBATCH -J split_intervals
#SBATCH -o %x.log
#SBATCH --time=01:00:00
#SBATCH --mem=1g

# Log Slurm job details
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

# Define memory for GATK4
# Minimum = 50% of memory
gatk_mem_min="$(( 5 * SLURM_MEM_PER_NODE / 10 ))M"
# Maximum = 90% of memory
gatk_mem_max="$(( 9 * SLURM_MEM_PER_NODE / 10 ))M"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Run GATK4's SplitIntervals
cmd=(
  gatk SplitIntervals
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  -R "$genome_local_unzip"
  --sequence-dictionary "$genome_dict"
  -O "$outdir"
  --scatter-count "$scatter"
  --subdivision-mode BALANCING_WITHOUT_INTERVAL_SUBDIVISION
)
echo "${cmd[*]}"
"${cmd[@]}"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoint
mkdir -p checkpoints
mapfile -t seqids < <(cut -f1 "$genome_idx")
n_seq="$(wc -l < "$genome_idx")"
n_seq_split="$(find "$outdir" -type f -exec grep -v "@" {} + | \
  grep -E -c "$(IFS='|'; echo "${seqids[*]}")")"
if [[ "$n_seq" -eq "$n_seq_split" ]]
then
  # Create list of interval filenames
  find "$outdir" -type f -name "[0-9][0-9][0-9][0-9]-scattered.interval_list" \
    | sort -h > "$intervals_list"
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - not all chromosomes found in split interval lists in $outdir"
  echo "Checkpoint not created."
  exit 1
fi
