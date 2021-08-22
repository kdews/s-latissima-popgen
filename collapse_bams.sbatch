#!/bin/bash
#SBATCH --mem=50g
#SBATCH --time=5-0
#SBATCH --cpus-per-task=2

genome=$1
genome_basename=$(basename -- $genome)
genome_base=`echo $genome_basename | sed 's/\..*//g'`
indiv_file=$2
indiv_id=`cat $indiv_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
indir=marked_dupes
outdir=collapsed_bams

# Load GATK4
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate gatk4
gatk --version
if [[ $? -ne 0 ]]
then
	printf "Error - check GATK4 installation.\n"
	exit 1
fi

# Create output directory
if [[ ! -d $outdir ]]
then
	mkdir $outdir
fi

# Generate array to hold list of BAMs associated with 
# the $indiv_id and the required "-I" flag before each
f=`ls ${indir}/*${indiv_id}*.sorted.marked.bam`
input_bams=(${f// / })
cnt=${#input_bams[@]}
for ((i=0;i<cnt;i++)); do
    input_bams[i]="-I ${input_bams[i]}"
done

# Run GATK4's MergeSamFiles
gatk MergeSamFiles ${input_bams[*]} \
-O ${outdir}/${indiv_id}_${genome_base}.sorted.marked.merged.bam \
--USE_THREADING --TMP_DIR collapse_bams_temp

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ -f \
${outdir}/${indiv_id}_${genome_base}.sorted.marked.merged.bam ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/collapse_bams_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		printf "Error - merged BAM file \
${outdir}/${indiv_id}_${genome_base}.sorted.marked.merged.bam \
not created.\n"
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by GATK4.\n"
	exit 1
fi

