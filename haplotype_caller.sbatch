#!/bin/bash
#SBATCH --mem=50g
#SBATCH --time=5-0

genome=$1
genome_basename=$(basename -- $genome)
genome_basename_unzip=`echo $genome_basename | sed 's/\.gz//g'`
genome_base=`echo $genome_basename | sed 's/\..*//g'`
indiv_file=$2
indiv_id=`cat $indiv_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
indir=collapsed_bams
outdir=gvcfs

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

# Run GATK4's HaplotypeCaller
gatk HaplotypeCaller -R hisat/${genome_basename_unzip} \
-I ${indir}/${indiv_id}_${genome_base}.sorted.marked.merged.bam \
-O ${outdir}/${indiv_id}_${genome_base}.g.vcf.gz \
--tmp-dir gvcfs_temp

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ -f \
${outdir}/${indiv_id}_${genome_base}.g.vcf.gz ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/haploytpe_caller_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		printf "Error - gVCF file \
${outdir}/${indiv_id}_${genome_base}.g.vcf.gz \
not created.\n"
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by GATK4.\n"
	exit 1
fi
