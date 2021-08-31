#!/bin/bash
#SBATCH --mem=5gb
#SBATCH --time=01:00:00

indir=$1 # input directory
id_file=$2
id=`cat $id_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
pattern=$3 # VCG/gVCF file ending pattern (e.g., .g.vcf, .vcf.gz)
# Note: input filenames must have an underscore following the unique ID
infile=`ls ${indir}/*${id}_*${pattern}`

# Load GATK4
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate gatk4
gatk --version
if [[ $? -ne 0 ]]
then
	echo "Error - check GATK4 installation."
fi

# Build index for input VCF/gVCF file
gatk IndexFeatureFile -I ${infile}

