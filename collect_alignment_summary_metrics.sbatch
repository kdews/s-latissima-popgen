#!/bin/bash
#SBATCH --time=02:00:00
#SBATCH --mem=2gb

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
genome_config="$4" # genome config file
samples_list="$5" # list of sample IDs

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

# Parse sample ID
sample_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$samples_list")"
# Input BAM file
in_bam="$indir/${sample_id}_$genome_base.sorted.bam"
# Output QC file named from sample ID
align_metrics="$outdir/${sample_id}_$genome_base.collect_alignment_summary.metrics"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version

# Run GATK4 CollectAlignmentSummaryMetrics on HISAT2 alignmnets
cmd=(
    gatk CollectAlignmentSummaryMetrics
    -R "$genome_local_unzip"
    -I "$in_bam"
    -O "$align_metrics"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoint
mkdir -p checkpoints
if [[ -f "$align_metrics" ]]
then
    echo "Creating checkpoint."
    touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
    exit 0
else
    echo "Error - Alignment Summay Metrics file ($align_metrics) for BAM ($in_bam) not found."
    echo "Checkpoint not created."
    exit 1
fi
