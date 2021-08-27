#!/bin/bash
#SBATCH --mem=50g
#SBATCH --time=10:00:00

prefix=$1 # sbatch filename without file extensions
indir=$2 # input directory
outdir=$prefix # parent output directory containing subdirectories
if [[ ! -d $outdir ]]
then
        mkdir $outdir
fi
# subdirectory for this job step
outdir=${prefix}/interval_${SLURM_ARRAY_TASK_ID} # output directory
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

# Create temp directory
if [[ ! -d $tempdir ]]
then
        mkdir $tempdir
fi

# Generate array to hold list all g.vcfs
# and the required "-V" flag before each
f=`ls ${indir}/*.g.vcf.gz`
input_gvcfs=(${f// / })
cnt=${#input_gvcfs[@]}
for ((i=0;i<cnt;i++)); do
    input_gvcfs[i]="-V ${input_gvcfs[i]}"
done

# Run GATK4's GenomicsDBImport
gatk GenomicsDBImport --java-options "-Xms39g -Xmx39g" \
-R $genome \
${input_gvcfs[*]} -L $intervals_file_chunk \
--genomicsdb-workspace-path $outdir \
--tmp-dir $tempdir

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ -d $outdir ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/${prefix}_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		echo "Error - Genomics Database Workspace \
$outdir not created."
		exit 1
	fi
else
	echo "Error - non-zero exit code returned by GATK4."
	exit 1
fi

