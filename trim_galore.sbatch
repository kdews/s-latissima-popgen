#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=1-0
#SBATCH --cpus-per-task=15

samples_file=$1
sample_id=`cat $samples_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
samples_dir=$2
reads1=${samples_dir}/${sample_id}_R1.fastq.gz
reads2=${samples_dir}/${sample_id}_R2.fastq.gz
outdir=$3

# Load trim_galore
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate trimgalore
trim_galore --version
if [[ $? -ne 0 ]]
then
  printf "Error - check Trim Galore! installation.\n\n"
fi

printf "Running Trim Galore! on 2 read files associated \
with ${sample_id}: \n\
$reads1 and ${reads2}.\n\n"

trim_galore --paired --phred33 --output_dir $outdir \
--length 36 --stringency 1 -e 0.1 -j 4 \
--fastqc_args "-t ${SLURM_CPUS_PER_TASK}" $reads1 $reads2

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ `ls ${outdir}/${sample_id}*` == 8 ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/trim_galore_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		printf "Error - not all reads trimmed \
for ${sample_id}."
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by Trim Galore!"
	exit 1
fi

