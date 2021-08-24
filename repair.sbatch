#!/bin/bash
#SBATCH --mem=500mb
#SBATCH --time=01:00:00

samples_file=$1
samples_dir=`realpath $2`
sample_id=`cat $samples_file | sort -u | sed -n ${SLURM_ARRAY_TASK_ID}p`
reads1=${samples_dir}/${sample_id}_R1.fastq.gz
reads2=${samples_dir}/${sample_id}_R2.fastq.gz

# Load repair.sh (in BBMap package)
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate bbmap
repair.sh --version
if [[ $? -ne 0 ]]
then
  printf "Error - check BBMap installation.\n"
fi

printf "Repairing 2 read files associated with \
${sample_id}:\n${reads1} and \n${reads2}.\n\n"

# Parse input FASTQs for naming output
reads1_prefix=`echo $(basename -- $reads1) | sed "s/\..*//"`
reads1_suffix=`echo $(basename -- $reads1) | sed "s/$reads1_prefix//"`
reads2_prefix=`echo $(basename -- $reads2) | sed "s/\..*//"`
reads2_suffix=`echo $(basename -- $reads2) | sed "s/$reads2_prefix//"`

# Run BBMap repair.sh
repair.sh in=$reads1 in2=$reads2 \
out=${samples_dir}/${reads1_prefix}.repaired${reads1_suffix} \
out2=${samples_dir}/${reads2_prefix}.repaired${reads2_suffix} \
outs=${samples_dir}/${sample_id}.singles${reads1_suffix}

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ `ls ${outdir}/${sample_id}*repaired* | wc -l` == 2 ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/trim_galore_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		printf "Error - not all reads repaired \
for ${sample_id}.\n"
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by repair.sh.\n"
	exit 1
fi

