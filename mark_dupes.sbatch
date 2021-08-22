#!/bin/bash
#SBATCH --time=2-0
#SBATCH --mem=50gb

genome=$1
genome_basename=$(basename -- $genome)
genome_base=`echo $genome_basename | sed 's/\..*//g'`
samples_file=$2
sample_id=`cat $samples_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
qc_dir=$3
indir=hisat2
outdir=mark_dupes

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

# Mark duplicates
gatk MarkDuplicates \
-I ${indir}/${sample_id}_${genome_base}.sorted.bam \
-O ${outdir}/${sample_id}_${genome_base}.sorted.marked.bam \
-M ${qc_dir}/${sample_id}_${genome_base}.mark_dupes.metrics \
--REMOVE_DUPLICATES --VALIDATION_STRINGENCY LENIENT

if [[ $? -eq 0 ]]
then
	if [[ -f ${outdir}/${sample_id}_${genome_base}.sorted.marked.bam ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/mark_dupes_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		printf "Error - duplicate-marked BAM not created \
for ${sample_id}.\n"
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by GATK4.\n"
	exit 1
fi
