#!/bin/bash
#SBATCH --mem=5gb
#SBATCH --time=08:00:00
#SBATCH --cpus-per-task=12
#SBATCH --exclusive

samples_file=$1
sample_id=`cat $samples_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
samples_dir=all_wgs
reads1=${samples_dir}/${sample_id}_R1.fastq.gz
reads2=${samples_dir}/${sample_id}_R2.fastq.gz
outdir=fastqc
logdir=${outdir}_logs

# Create FASTQC output directory (if needed)
if [[ -d $outdir ]]
then
  printf "Detected output directory ${outdir}.\n\n"
else
  printf "Creating output directory ${outdir}.\n\n"
  mkdir $outdir 
fi

# Load fastqc
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate fastqc
fastqc --version
if [[ $? -ne 0 ]]
then
  printf "Error - check FASTQC installation.\n\n"
else
  printf "FASTQC loaded successfully.\n\n"
fi

printf "Running FASTQC on 2 read files associated \
with ${sample_id}: \n $reads1 and ${reads2}.\n\n"

fastqc -t $SLURM_CPUS_PER_TASK -o fastqc $reads1 $reads2

