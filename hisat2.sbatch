#!/bin/bash
#SBATCH --time=10:00:00
#SBATCH --mem=50g
#SBATCH --cpus-per-task=12

# Print date and time
date
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory
samples_list="$5" # list of sample IDs
qc_dir="$6" # directory to write QC output
indiv_list="$7" # file to write parsed individual IDs

# Create output and QC directories (if needed)
mkdir -p "$outdir"
mkdir -p "$qc_dir"

# Source genome config
if [[ -f "$genome_config" ]]
then
  source "$genome_config"
else
  echo "Error on source of genome config: $genome_config"
  exit 1
fi

# Parse sample ID and trimmed read filenames
sample_id="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$samples_list")"
reads1="$indir/${sample_id}_R1_val_1.fq.gz"
reads2="$indir/${sample_id}_R2_val_2.fq.gz"
# Output BAM named from sample ID
out_bam="$outdir/${sample_id}_$genome_base.sorted.bam"
# Output QC summary file named from sample ID
out_summary="$qc_dir/${sample_id}_$genome_base.hisat2.summary"

# Define memory per thread for samtools sort
mem_per_thread="$(( 9 * SLURM_MEM_PER_NODE / SLURM_JOB_CPUS_PER_NODE / 10000 ))G"

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
hisat2 --version || exit 1
samtools --version || exit 1

# Define read groups for SAM headers from sample ID and FASTQ file read IDs
echo "Parsing read groups from sample ID ($sample_id) and associated read files:"
echo "1: $reads1"
echo "2: $reads2"
# Input sample ID format = UniqueID_SampleID_Sequencer_Barcode_Plate_Lane_Read 
# Create array 'rgs1' from sample ID by splitting on '_'
IFS='_' read -r -a rgs1 <<< "$sample_id"
# Read first line of FASTQ to get read ID
read_id="$(zcat "$reads1" | head -n1 | awk '{print $1}' | sed 's/@//g')"
# Create array 'rgs2' from read ID by splitting on ':'
IFS=':' read -r -a rgs2 <<< "$read_id"
# Index rgs1 (sample ID array) and rgs2 (read ID array) to generate read group values
# Read group ID = {FLOWCELL_BARCODE}.{LANE}
rg_id="${rgs2[2]}.${rgs2[3]}"
echo "Read group ID = ID:$rg_id"
# Read group SaMple name (SM) = shortened SampleID within input sample ID (no UniqueID)
rg_sm="${rgs1[1]}"
echo "Read group sample name = SM:$rg_sm"
# Save parsed individual ID to index file
echo "$rg_sm" >> "$indiv_list"
# Read group Platform Unit (PU) = {FLOWCELL_BARCODE}.{LANE}.{SAMPLE_NAME}
rg_pu="${rgs2[2]}.${rgs2[3]}.${rgs1[1]}"
echo "Read group platform unit = PU:$rg_pu"
# Read group LiBrary identifier = SampleID-UniqueID
rg_lb="${rgs1[1]}-${rgs1[0]}"
echo "Read group library identifier = LB:$rg_lb"
# Read group PLatform (PL) = ILLUMINA
rg_pl="ILLUMINA"
echo "Read group platform = PL:$rg_pl"

# Run HISAT2 and pipe output to samtools sort
echo
echo "Running HISAT2 on read files associated with sample ID: $sample_id"
echo "1: $reads1" 
echo "2: $reads2"
hisat2_cmd=(
  hisat2
  -p "$SLURM_CPUS_PER_TASK"
  --time
  -x "$ht2_idx"
  -1 "$reads1"
  -2 "$reads2"
  --rg-id "$rg_id"
  --rg "SM:$rg_sm"
  --rg "LB:$rg_lb"
  --rg "PU:$rg_pu"
  --rg "PL:$rg_pl"
  --new-summary
  --summary-file "$out_summary"
)
samtools_cmd=(
  samtools sort
  -@ "$SLURM_CPUS_PER_TASK"
  -m "$mem_per_thread"
  -O bam
  -o "$out_bam"
)
echo "${hisat2_cmd[*]} | ${samtools_cmd[*]}"
"${hisat2_cmd[@]}" | "${samtools_cmd[@]}"

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
  echo "Error - alignment not completed for sample ID: $sample_id"
  echo "Checkpoint not created."
  exit 1
fi
