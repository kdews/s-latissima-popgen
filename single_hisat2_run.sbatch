#!/bin/bash
#SBATCH --time=1-0
#SBATCH --mem=120g
#SBATCH --cpus-per-task=5

genome=$1
genome_basename=$(basename -- $genome)
genome_base=`echo $genome_basename | sed 's/\..*//g'`
samples_file=$2
trimmed_dir=$3
qc_dir=save_bams
indiv_file=$5
outdir=save_bams
array_num=$6
sample_id=`cat $samples_file | sed -n ${array_num}p`
reads1=${trimmed_dir}/${sample_id}_R1_val_1.fq.gz
reads2=${trimmed_dir}/${sample_id}_R2_val_2.fq.gz
# Define memory per thread for samtools sort
mem_per_thread="$(( 9 * $SLURM_MEM_PER_NODE / \
$SLURM_JOB_CPUS_PER_NODE / 10000 ))G"

# Load HISAT2
source ~/bin/anaconda3/etc/profile.d/conda.sh
conda activate hisat2
hisat2 --version
if [[ $? -ne 0 ]]
then
	printf "Error - check HISAT2 installation.\n"
	exit 1
fi

printf "Running HISAT2 on 2 read files associated \
with ${sample_id}: \n\
$reads1 and \n\
${reads2}.\n\n"

# Define read groups for SAM headers from input $sample_id
# and input FASTQ file read IDs
# Input sample ID format = UniqueID_SampleID_Sequencer_Barcode_Plate_Lane_Read 
# Create array 'rgs' from $sample_id by splitting on '_'
rgs1=(${sample_id//_/ })
read_id=`zcat $reads1 | head -n1 | awk '{print $1}' | sed 's/@//g'`
rgs2=(${read_id//:/ })
# Index both $sample_id array and read ID array to generate read group values
# Read group ID = {FLOWCELL_BARCODE}.{LANE}
rg_id="${rgs2[2]}.${rgs2[3]}"
printf "Read group ID = ID:${rg_id}\n"
# Read group SaMple name (SM) = shortened SampleID within input $sample_id (no UniqueID)
rg_sm="${rgs1[1]}"
printf "Read group sample name = SM:${rg_sm}\n"
echo "$rg_sm" >> $indiv_file
# Read group Platform Unit (PU) = {FLOWCELL_BARCODE}.{LANE}.{SAMPLE_NAME}
rg_pu="${rgs2[2]}.${rgs2[3]}.${rgs1[1]}"
printf "Read group platform unit = PU:${rg_pu}\n"
# Read group LiBrary identifier = SampleID-UniqueID
rg_lb="${rgs1[1]}-${rgs1[0]}"
printf "Read group library identifier = LB:${rg_lb}\n"
# Read group PLatform (PL) = ILLUMINA
rg_pl="ILLUMINA"
printf "Read group platform = PL:${rg_pl}\n\n"

# Run HISAT2 & pipe output to samtools
cd $outdir
hisat2 -p ${SLURM_CPUS_PER_TASK} \
-x $genome_base -1 ../${reads1} -2 ../${reads2} \
--rg-id=${rg_id} --rg SM:${rg_sm} --rg LB:${rg_lb} \
--rg PU:${rg_pu} --rg PL:${rg_pl} \
--summary-file=../${qc_dir}/${sample_id}_${genome_base}.hisat2.summary | \
samtools sort -O BAM -@ ${SLURM_CPUS_PER_TASK} -m ${mem_per_thread} \
-T ${sample_id}_${genome_base} -o ${sample_id}_${genome_base}.sorted.bam

# Checkpoint
if [[ $? -eq 0 ]]
then
	cd ..
	if [[ -f ${outdir}/${sample_id}_${genome_base}.sorted.bam ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch \
checkpoints/hisat2_${array_num}.checkpoint
		exit 0
	else
		printf "Error - sorted BAM file not created \
for ${sample_id}.\n"
		exit 1
	fi
else
	printf "Error - non-zero exit code returned by HISAT2.\n"
	exit 1
fi

