#!/bin/bash
#SBATCH --mem=50gb
#SBATCH --time=1-0

qc_dir=$1
# Optional, to specify directory containing scripts
scripts_dir=$2/

# Load multiqc
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate multiqc
multiqc --version
if [[ $? -ne 0 ]]
then
  printf "Error - check MultiQC installation.\n\n"
fi

multiqc -c ${scripts_dir}multiqc_config.yaml \
-o $qc_dir $qc_dir

# Checkpoints
if [[ $? -eq 0 ]]
then
	if [[ -f ${qc_dir}/multiqc_report.html  ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch checkpoints/multiqc.checkpoint
		exit 0
	else
		printf "Error - MultiQC report not created.\n"
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by MultiQC.\n"
	exit 1
fi

