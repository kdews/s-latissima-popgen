#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=1-0
#SBATCH --cpus-per-task=15

genome=$1
genome_base=`echo $genome_basename | sed 's/\..*//g'`
samples_file=$2
sample_id=`cat $samples_file | sed -n ${SLURM_ARRAY_TASK_ID}p`
trimmed_dir=$3
reads1=${trimmed_dir}/${sample_id}_R1_val_1.fq.gz
reads2=${trimmed_dir}/${sample_id}_R2_val_2.fq.gz
logdir=hisat2_logs

# Load HISAT2
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate hisat2
hisat2 --version
if [[ $? -ne 0 ]]
then
  printf "Error - check HISAT2 installation.\n"
fi

printf "Running HISAT2 on 2 read files associated \
with ${sample_id}: \n\
$reads1 and ${reads2}.\n\n"

# Define read groups for SAM headers from input $sample_id
# and input FASTQ file read IDs
# Input sample ID format = UniqueID_SampleID_Sequencer_Barcode_Plate_Lane_Read 
# Create array 'rgs' from $sample_id by splitting on '_'
rgs1=(${sample_id//_/ })
read_id=`zcat $reads1 | head -n1 | awk '{print $1}' | sed 's/@///g'`
rgs2=(${read_id//:/ })
# Index both $sample_id array and read ID array to generate read group values
# Read group ID = {FLOWCELL_BARCODE}.{LANE}
rg_id="${rgs2[2]}.${rgs2[3]}"
# Read group SaMple name (SM) = shortened SampleID within input $sample_id (no UniqueID)
rg_sm="${rgs1[1]}"
# Read group Platform Unit (PU) = {FLOWCELL_BARCODE}.{LANE}.{SAMPLE_NAME}
rg_pu="${rgs2[2]}.${rgs2[3]}.${rgs1[1]}"
# Read group LiBrary identifier = SampleID-UniqueID
rg_lb="${rgs1[1]}-${rgs1[0]}"
# Read group PLatform (PL) = ILLUMINA
rg_pl="ILLUMINA"

# Run HISAT2
hisat2 -p ${SLURM_CPUS_PER_TASK} \
-x $genome_base -1 $reads1 -2 $reads2 \
-S ${sample_id}_${genome_base}.sam \
--rg-id=${rg_id} --rg SM:${rg_sm} --rg LB:${rg_lb} \
--rg PU:${rg_pu} --rg PL:${rg_pl} \
--summary-file=${logdir}/${sample_id}_${genome_base}.hisat2.summary

# Checkpoint
if [[ $? -eq 0 ]]
then
	if [[ -f ${sample_id}_${genome_base}.sam ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/hisat2_${SLURM_ARRAY_TASK_ID}.checkpoint
		exit 0
	else
		printf "Error - SAM file not created \
for ${sample_id}."
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by HISAT2.\n"
	exit 1
fi

