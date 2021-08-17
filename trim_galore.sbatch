#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=1-0
#SBATCH --cpus-per-task=12

samples_file=$1
sample_id=`cat $samples_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
samples_dir=$2
reads1=${samples_dir}/${sample_id}_R1.fastq.gz
reads2=${samples_dir}/${sample_id}_R2.fastq.gz
fastqc_dir=$3
outdir=trimmed_reads
logdir=trim_galore_logs

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

# Create trimmed reads output directory (if needed)
if [[ ! -d $outdir ]]
then
  printf "Creating output directory ${outdir}.\n\n"
  mkdir $outdir 
fi

trim_galore --paired --phred33 --output_dir $outdir \
--length 36 --stringency 1 -e 0.1 \
--fastqc_args "-o $fastqc_dir" \
$reads1 $reads2

