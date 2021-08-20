#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=1-0
#SBATCH --mem=40g
#SBATCH --cpus-per-task=12

genome=$1
genome_basename=$(basename -- $genome)
genome_base=`echo $genome_basename | sed 's/\..*//g'`

# Load HISAT2
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate hisat2
hisat2 --version
if [[ $? -ne 0 ]]
then
  printf "Error - check HISAT2 installation.\n"
fi

printf "Copying $genome to genome/.\n"
if [[ -d genome ]]
then
	mkdir genome
fi
if [[ -f genome/$(basename -- $genome) ]]
then
	cp $genome genome/
fi

printf "Running HISAT2-build on genome file: $(basename -- $genome)\n"\
cd genome/
hisat2-build -p ${SLURM_CPUS_PER_TASK} $genome_basename $genome_base
cd ..

# Checkpoint
files_exist () {
	if compgen -G "genome/${1}*.ht*" > /dev/null
	then
		echo "true"
	else
		echo "false"
	fi
}

if [[ $? -eq 0 ]]
then
	if [[ `files_exist ${genome_base}` == true ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/hisat2_build.checkpoint
		exit 0
	else
		printf "Error - .ht* files not detected in 'genome' \
directory. Checkpoint not created.\n"
	fi
else
	printf "Error - non-zero exit code returned by HISAT2-build.\n"
	exit 1
fi

