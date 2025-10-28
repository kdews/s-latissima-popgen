#!/bin/bash
#SBATCH --mem=50g
#SBATCH --time=1-0

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # parent output directory containing subdirectories
genome="$4" # genome FASTA
intervals_list="$5" # text file listing interval filenames
gvcf_list="$6" # list of gVCF filenames

# Name temp directory after job name
tempdir="${prefix}_tmp"

# Create parent output and temp directories (if needed)
mkdir -p "$outdir"
mkdir -p "$tempdir"

# Subdirectory for this job step
outdir="$outdir/interval_$SLURM_ARRAY_TASK_ID"
# Parse genome filename
genome_basename="$(basename "$genome")"
genome_base="${genome_basename%%.*}"
genome_path=$(dirname "$genome")
# Parse interval
interval="$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$intervals_list")"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version

## Generate array to hold list all g.vcfs
## and the required "-V" flag before each
#f=`ls ${indir}/*.g.vcf.gz`
#input_gvcfs=(${f// / })
#cnt=${#input_gvcfs[@]}
#for ((i=0;i<cnt;i++)); do
#    input_gvcfs[i]="-V ${input_gvcfs[i]}"
#done

# Run GATK4's GenomicsDBImport
cmd=(
	gatk GenomicsDBImport
	--java-options "-Xms39g -Xmx39g"
	-R "$genome"
	--sequence-dictionary "$genome_path/$genome_base.dict"
	-L "$interval"
	-V "$gvcf_list"
	--genomicsdb-workspace-path "$outdir"
	--tmp-dir "$tempdir"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoint
mkdir -p checkpoints
if [[ -d "$outdir" ]]
then
	echo "Creating checkpoint."
	touch "checkpoints/${prefix}_$SLURM_ARRAY_TASK_ID.checkpoint"
	exit 0
else
	echo "Error - output Genomics Database Workspace ($outdir) not found."
	echo "Checkpoint not created."
	exit 1
fi

