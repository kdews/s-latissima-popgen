#!/bin/bash
#SBATCH --time=1-0
#SBATCH --mem=75g
#SBATCH --cpus-per-task=5

genome=$1
genome_basename=$(basename -- $genome)
genome_base=`echo $genome_basename | sed 's/\..*//g'`
samples_file=$2
outdir=hisat2
array_num=$3
sample_id=`cat $samples_file | sed -n ${array_num}p`
# Define memory per thread for samtools sort
mem_per_thread="$(( 9 * $SLURM_MEM_PER_NODE / \
$SLURM_JOB_CPUS_PER_NODE / 10000 ))G"

# Load samtools
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate samtools
samtools --version
if [[ $? -ne 0 ]]
then
	printf "Error - check samtools installation.\n"
	exit 1
fi

# Convert SAM to BAM & sort by coordinate with samtools
samtools sort -O BAM \
-@ ${SLURM_CPUS_PER_TASK} -m ${mem_per_thread} \
-T ${outdir}/${sample_id}_${genome_base} \
-o ${outdir}/${sample_id}_${genome_base}.sorted.bam \
${outdir}/${sample_id}_${genome_base}.sam

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ -f ${outdir}/${sample_id}_${genome_base}.sorted.bam ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/hisat2_${array_num}.checkpoint
		exit 0
	else
		printf "Error - sorted BAM file not created \
for ${sample_id}.\n"
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by samtools.\n"
	exit 1
fi

