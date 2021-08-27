#!/bin/bash
#SBATCH --mem=50g
#SBATCH --time=5-0

prefix=$1 # sbatch filename without file extensions
indir=$2 # input directory
outdir=$3 # output directory
genome=$4
genome_basename=$(basename -- $genome)
genome_base=`echo $genome_basename | sed 's/\..*//g'`
interval_chunk_dir=$5
intervals_file=$6
intervals_file_chunk=${interval_chunk_dir}/${SLURM_ARRAY_TASK_ID}_${intervals_file}
tempdir=${outdir}_tmp

# Load GATK4
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate gatk4
gatk --version
if [[ $? -ne 0 ]]
then
	echo "Error - check GATK4 installation."
	exit 1
fi

# Create output directory
if [[ ! -d $outdir ]]
then
	mkdir $outdir
fi

# CombineGVCFs option
# -V ${indir}/interval_${SLURM_ARRAY_TASK_ID}_${genome_base}.g.vcf.gz \
# Run GATK4's GenotypeGVCFs
# GenomicsDBImport option
gatk GenotypeGVCFs -R ${genome} \
-V genomicsdbimport/interval_${SLURM_ARRAY_TASK_ID} \
-L ${intervals_file_chunk} \
-O ${outdir}/interval_${SLURM_ARRAY_TASK_ID}_${genome_base}.vcf.gz \
--tmp-dir ${prefix}_temp

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ -f \
${outdir}/interval_${SLURM_ARRAY_TASK_ID}_${genome_base}.vcf.gz ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/${prefix}_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		printf "Error - VCF file \
${outdir}/interval_${SLURM_ARRAY_TASK_ID}_${genome_base}.vcf.gz \
not created.\n"
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by GATK4.\n"
	exit 1
fi

