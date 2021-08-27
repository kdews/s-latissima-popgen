#!/bin/bash
#SBATCH --mem=100g
#SBATCH --time=2-0

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

# Create output and temp directories
if [[ ! -d $outdir ]]
then
        mkdir $outdir
fi
if [[ ! -d $tempdir ]]
then
        mkdir $tempdir
fi

# Generate array to hold list of all gVCFs
# and the required "-V" flag before each
f=`ls ${indir}/*.g.vcf.gz`
input_gvcfs=(${f// / })
cnt=${#input_gvcfs[@]}
for ((i=0;i<cnt;i++)); do
    input_gvcfs[i]="-V ${input_gvcfs[i]}"
done

# Run GATK4's CombineGVCFs
gatk CombineGVCFs --java-options "-Xms75g -Xmx75g"\
-R $genome \
${input_gvcfs[*]} -L $intervals_file_chunk \
-O ${outdir}/interval_${SLURM_ARRAY_TASK_ID}_${genome_base}.g.vcf.gz \
--tmp-dir $tempdir

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ -f \
${outdir}/interval_${SLURM_ARRAY_TASK_ID}_${genome_base}.g.vcf.gz ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/${prefix}_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		echo "Error - gVCF file \
${outdir}/interval_${SLURM_ARRAY_TASK_ID}_${genome_base}.g.vcf.gz \
not created."
		exit 1
	fi
else
	echo "Error - non-zero exit code returned by GATK4."
	exit 1
fi

