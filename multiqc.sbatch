#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=01:00:00

samples_file=$1
sample_id=`cat $samples_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
samples_dir=$2
reads1=${samples_dir}/${sample_id}_R1.fastq.gz
reads2=${samples_dir}/${sample_id}_R2.fastq.gz
input_dir=$3
logdir=${outdir}_logs

# Load multiqc
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate multiqc
multiqc --version
if [[ $? -ne 0 ]]
then
  printf "Error - check MultiQC installation.\n\n"
fi

# Create output directory (if needed)
if [[ ! -d $outdir ]]
then
	printf "Creating output directory ${outdir}.\n\n"
	mkdir $outdir 

multiqc --interactive -o ${input_dir}_multiqc \
-n ${input_dir}_multiqc.html $input_dir

