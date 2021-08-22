#!/bin/bash
#SBATCH --mem=50g
#SBATCH --time=5-0

genome=$1
genome_basename=$(basename -- $genome)
genome_basename_unzip=`echo $genome_basename | sed 's/\.gz//g'`
genome_base=`echo $genome_basename | sed 's/\..*//g'`
interval=$2
indir=gvcfs

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

# Create array of input gVCFs
input_gvcfs=""

# Run GATK4's CombineGVCFs
gatk CombineGVCFs -R hisat/${genome_basename_unzip} \
-V $input_gvcfs --intervals $interval \
-O ${indir}/${interval}_${genome_base}.g.vcf.gz \
--tmp-dir gvcfs_temp

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ -f \
${outdir}/${interval}_${genome_base}.g.vcf.gz ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/gvcf_combine_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		printf "Error - gVCF file \
${outdir}/${interval}_${genome_base}.combined.g.vcf.gz \
not created.\n"
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by GATK4.\n"
	exit 1
fi

