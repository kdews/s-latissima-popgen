#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=01:00:00

input_dir=$1
scripts_dir=$2

# Load multiqc
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate multiqc
multiqc --version
if [[ $? -ne 0 ]]
then
  printf "Error - check MultiQC installation.\n\n"
fi

multiqc -c ${scripts_dir}/multiqc_config.yaml \
-o ${input_dir}/multiqc_data \
-n ${input_dir}/multiqc.html $input_dir

