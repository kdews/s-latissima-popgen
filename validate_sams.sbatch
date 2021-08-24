#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=05:00:00

genome=$1
#genome=/scratch2/kdeweese/latissima/popgen_all/hisat2/SlaSLCT1FG3_1_AssemblyScaffolds_Repeatmasked.fasta
id_file=$2
id=`cat $id_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
indir=$3
pattern=$4
infile=`ls ${indir}/*${id}*${pattern}*am`
#indir=/scratch2/kdeweese/latissima/popgen_all/hisat2
#indir=/scratch2/kdeweese/latissima/popgen_all/mark_dupes
#indir=/scratch2/kdeweese/latissima/popgen_all/collapsed_bams
outdir=validate_sams

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

# Define input file with ID
infile_basename=$(basename -- $infile)

# Run GATK4's ValidateSamFile
gatk ValidateSamFile -M VERBOSE \
-I $infile \
-O ${outdir}/${infile_basename}.validate.verbose
