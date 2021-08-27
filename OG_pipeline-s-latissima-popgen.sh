#!/bin/bash
#SBATCH -p cegs
#SBATCH --time=3-0
#SBATCH -J queen
#SBATCH -o %x.log

## Saccharina latissima SNP calling pipeline
# A SLURM- and conda-dependent pipeline with sequential job
# steps linked by dependencies and checkpoint files

# Help message
if [[ $1 = "-h" ]] || [[ $1 = "--help" ]]
then
	printf "\
Takes as input a genome and path to directory containing (gzipped) \n\
FASTQ files, and outputs...\n\
 - individuals_file.txt - master file to index individual IDs\n\
 - wgs/\n\
	*.fastq.gz - FASTQ copies renamed to succinct sample IDs\n\
	*.repaired.fastq.gz - FASTQ read pairs repaired with repair.sh\n\
	samples_file.txt - master file to index sample IDs\n\
 - trimmed_reads/\n\
	*_val_1/2.fq.gz - reads post quality and adapter trimming by Trim Galore!\n\
 - bams\n\
	*.ht2 - indexed genome\n\
	*sorted.bam - sorted alignment files of trimmed reads to genome\n\
	*sorted.marked.bam - sorted alignment files with duplicates marked\n\
	*sorted.marked.merged.bam - sorted alignment files merged by individual\n\
 - gvcfs/\n\
	*.g.vcf.gz - genome variant call files (gVCFs) for each individual\n\
 - genotyped_vcfs\n\
	*vcf.gz - variant call files (VCFs) for each individual\n\
 - quality_control/\n\
	*_fastqc.zip/html - FastQC reports for all input FASTQs\n\
	*_val_1/2_fastqc.zip/html - FASTQC reports for trimmed FASTQs\n\
	*_trimming_report.txt - Trim Galore! report\n\
	*.hisat2.summary - HISAT2 report\n\
	multiqc_report.html - MultiQC report summarizing QCs at each step\n\
 - *_logs/\n\
	*.log - SLRUM log files from inividual job step submissions\n\
 - checkpoints/\n\
	*.checkpoint - checkpoint file(s) for job step, \
created upon job completion\n\
Usage: sh pipeline_template.sh\n\n\
Assumes SBATCH files will be named with convention: \
<prefix>.sbatch (e.g., fastqc.sbatch).\n\
Log files will be saved to the directory <prefix>_logs,\n\
and named <prefix>_<sample_idx>.out\n"
	exit 0
fi


# Define global variables and functions
# User defined
genome=/project/noujdine_61/kdeweese/latissima/Assembly/Assembled_scaffolds__masked_/SlaSLCT1FG3_1_AssemblyScaffolds_Repeatmasked.fasta.gz
path_to_raw_reads=/project/noujdine_61/kdeweese/latissima/all_wgs_OG_names
# Optional, specifies directory containing scripts, MUST end in "/"
scripts_dir=s-latissima-popgen/ # don't set if you don't plan to use it
partition="cegs"
user_id=`whoami`
# Specific to pipeline
pipeline_log=queen.log
num_samples=`expr $(ls ${path_to_raw_reads}/*fastq.gz | wc -l) / 2`
samples_dir=wgs
samples_file=${samples_dir}/samples_file.txt
indiv_file=individuals_file.txt
qc_dir=quality_control
trimmed_dir=trimmed_reads
bams_dir=bams
gvcfs_dir=gvcfs
# Define function to return prefix of input file
get_prefix () {
	local filename=`basename -- $1`
	local filename="${filename%.*}"
	echo $filename
}
# Define function to make a log directory from an input string
# (e.g., prefix), but only if it doesn't already exist
make_logdir () {
	local logdir=${1}_logs
	# Create log directory (if needed)
	if [[ ! -d $logdir ]]
	then
		mkdir $logdir
	fi
	echo "$logdir"
}
# Define function for array or non-array submission
# that returns the jobid but takes no dependencies
no_depend () {
	# Define job type
	# Determine array size for all batch jobs
	# (e.g., number of samples)
	if [[ $1 == "--array" ]]
	then
		# Inputs
		local array_size=$2
		if [[ `echo $array_size | sed 's/,/ /g' | wc -w` -eq 1 ]]
		then
			array_size="1-${array_size}"
		fi
		local sbatch_file=$3
		# Takes prefix of SBATCH file
		local prefix=`get_prefix $sbatch_file`
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable --array=${array_size} -o ${logdir}/%x_%a.out \
$sbatch_file "${@:4}"`
	else
		# Inputs
		local sbatch_file=$1
		# Takes prefix of SBATCH file
		local prefix=`get_prefix $sbatch_file`
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable -o ${logdir}/%x.out $sbatch_file "${@:2}"`
	fi
	echo "$jobid"
}
# Define function for array or non-array submission
# that takes a dependency and returns a jobid
depend () {
	# Define job type
	if [[ $1 == "--array" ]]
	then
		# Inputs
		local array_size=$2
		if [[ `echo $array_size | sed 's/,/ /g' | wc -w` -eq 1 ]]
		then
			array_size="1-${array_size}"
		fi
		local sbatch_file=$3
		local dep_jobid=$4
		# Takes prefix of SBATCH file
		local prefix=`get_prefix $sbatch_file`
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable --array=${array_size} -o ${logdir}/%x_%a.out \
--dependency=afterok:${dep_jobid} $sbatch_file "${@:5}"`
	else
		# Inputs
		local sbatch_file=$1
		local dep_jobid=$2
		# Takes prefix of SBATCH file
		local prefix=`get_prefix $sbatch_file`
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable -o ${logdir}/%x.out --dependency=afterok:${dep_jobid} \
$sbatch_file "${@:3}"`
	fi
	echo "$jobid"
}
# Define function to check for existence of a set of 
# similarly named checkpoint files with a wildcard
checkpoints_exist () {
	prefix=$1
	if [[ -z $prefix ]]
	then
		printf "Error - no prefix supplied to \
checkpoints_exist function.\n"
		exit 1
	fi
	if compgen -G "checkpoints/${prefix}*.checkpoint" > /dev/null
	then
		echo "true"
	else
		echo "false"
	fi
}
# Define function to check for and remove a set of 
# similarly named checkpoint files
wipecheckpoints () {
	if [[ `checkpoints_exist $1` == "true" ]]
        then
                rm checkpoints/${1}*.checkpoint
        fi
}
# Define function to check for a set of similarly named 
# checkpoint files and return missing array indices
missingcheckpoints () {
	# $1 is input_prefix
	# $2 is array_size
	if [[ `checkpoints_exist $1` == "true" ]]
	then
		local total=`seq 1 1 "$2"`
		for i in `echo "$total"`
		do
			[[ -f checkpoints/${1}_${i}.checkpoint ]] || printf "${i},"
		done
	else
		echo "Error - no checkpoints found for ${1}."
		exit 1
	fi
}
# Define function to run an array job step with a set number of 
# checkpoints files as a "dependency" (e.g., wait steps)
# (This avoids QOSMax errors from SLURM with next to zero use of storage)
pipeliner () {
	if [[ $1 = "--array" ]]
	then
		local array_indices=$2
		local dependency_prefix=$3
		local dependency_size=$4
		local sleep_time=$5
		local input_sbatch=$6
		local trailing_args="${@:7}"
	else
		local dependency_prefix=$1
		local dependency_size=$2
		local sleep_time=$3
		local input_sbatch=$4
		local trailing_args="${@:5}"
	fi
	local input_prefix=`get_prefix $input_sbatch`
	until [[ `checkpoints_exist $dependency_prefix` = "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $dependency_size ]]
	do
		{ date & printf "Waiting for completion of $dependency_prefix \
step.\n"; } >> $pipeline_log
		sleep $sleep_time
	done
	if [[ `checkpoints_exist $input_prefix` = "true" ]]
	then
		echo "$input_prefix `checkpoints_exist $input_prefix`" >> $pipeline_log
		local num_checks=`ls checkpoints/${input_prefix}*.checkpoint | wc -l`
		{ date & printf "${num_checks} checkpoint(s) detected for ${input_prefix}. \
Validating...\n"; } >> $pipeline_log
		if [[ $1 = "--array" ]] && [[ $array_indices ]] && \
[[ $num_checks -ne $array_indices ]] 
		then
			local array_flag="${1} `missingcheckpoints $input_prefix $array_indices`"
		printf "Error detected in ${input_prefix} checkpoint. \
Restarting step at checkpoint.\n" >> $pipeline_log
		echo "Submitting job array indices: $array_indices" >> $pipeline_log
		local jobid="no_depend $array_flag $input_sbatch $trailing_args"
		elif [[ $num_checks -eq $array_indices ]]
		then
			{ date & printf "${input_prefix} run already completed. \
Skipping.\n"; } >> $pipeline_log
		elif [[ $1 != "--array" ]] && [[ $num_checks -eq 1 ]]
		then
			{ date & printf "${input_prefix} run already completed. \
Skipping.\n"; } >> $pipeline_log
		else
			echo "Error - check inputs to 'pipeliner'." >> $pipeline_log
		fi
	else
		[[ $1 = "--array" ]] && [[ $array_indices ]] && \
local array_flag="${1} ${array_indices}"
		{ date & printf "Beginning ${input_prefix} step.\n"; } >> $pipeline_log
#		wipecheckpoints $input_prefix
		local jobid=`no_depend $array_flag $input_sbatch $trailing_args`
	fi
	echo $jobid
}


# Run pipeline
# Set array size for working with sample IDs
array_size=$num_samples
{ date & printf "Array size set to ${num_samples}.\n"; } > $pipeline_log

# Rename reads and create $samples_file
input_sbatch=${scripts_dir}rename.sbatch
input_prefix=`get_prefix $input_sbatch`
# Before running, check if run has already succeeded
if [[ -f $samples_file ]] && \
[[ `checkpoints_exist $input_prefix` == "true" ]]
then
	{ date & printf "Checkpoint and $samples_file detected. \
Skipping ${input_prefix} step.\n";} >> $pipeline_log
else
#	wipecheckpoints $input_prefix
	{ date & printf "Renaming: Files in $path_to_raw_reads copied \
into $samples_dir and renamed.\n"; } >> $pipeline_log 
#	rename_jobid=`no_depend $input_sbatch \
#$path_to_raw_reads $samples_dir $samples_file $scripts_dir`
fi

# Repair FASTQs with BBMap repair.sh
dependency=$rename_jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}repair.sbatch
input_prefix=`get_prefix $input_sbatch`
sleep_time=600
#repair_jobid=``
pipeliner --array $array_size $dependency_prefix 1 \
$sleep_time $input_sbatch \
$samples_file $samples_dir

# FastQC
# Depend start upon last job step
dependency=$repair_jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}fastqc.sbatch
input_prefix=`get_prefix $input_sbatch`
sleep_time=600
#fastqc_jobid=``
pipeliner --array $array_size $dependency_prefix $array_size \
$sleep_time $input_sbatch \
$samples_file $samples_dir $qc_dir

#input_prefix=`get_prefix $input_sbatch`
## Check for known dependency
#if [[ $dependency ]]
#then
#	date
#	printf "Running FastQC on raw reads in ${samples_dir} following \
#completion of $dependency_prefix job (jobid $dependency).\n"
#	fastqc_jobid=`depend --array $array_size \
#${scripts_dir}/${input_sbatch} $dependency $samples_file \
#$samples_dir $qc_dir`
## If dependency is finished running, verify its checkpoint and $samples_file
#elif [[ -f $samples_file ]] && \
#[[ `checkpoints_exist $dependency_prefix` == "true" ]]
#then
#	# Now check for any existing checkpoints for this step
#	if [[ `checkpoints_exist $input_prefix` == "true" ]]
#	then
#		printf "Checkpoint detected for ${input_prefix}. Validating...\n"
#		# If required number of checkpoints not met, erase existing
#		if [[ `ls checkpoints/${input_prefix}*.checkpoint | \
#wc -l` -ne $num_samples ]]
#		then
#			wipecheckpoints $input_prefix
#			date
#			printf "Eror detected in ${input_prefix} checkpoint. \
#Rerunning ${input_prefix} on raw reads in ${samples_dir}.\n"
#			fastqc_jobid=`no_depend --array $array_size \
#${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir`
#		elif [[ `ls checkpoints/${input_prefix}*.checkpoint | \
#wc -l` -eq $num_samples ]]
#		then
#			date
#			printf "${input_prefix} run already completed. Skipping.\n"
#		fi
#	else
#		wipecheckpoints $input_prefix
#		date
#		printf "Running FastQC on raw reads in ${samples_dir}.\n"
#		fastqc_jobid=`no_depend --array $array_size \
#${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir`
#	fi
#else
#	printf "Error - either $samples_file or \
#dependency checkpoint are missing.\n"
#	exit 1
#fi

# Quality and adapter trimming
# Depend start upon last job step
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}trim_galore.sbatch
input_prefix=`get_prefix $input_sbatch`
sleep_time=600
#trim_galore_jobid=``
pipeliner --array $array_size $dependency_prefix $array_size \
$sleep_time $input_sbatch \
$samples_file $samples_dir $qc_dir $trimmed_dir
dependency_size=$array_size

#input_prefix=`get_prefix $input_sbatch`
#until [[ -f $samples_file ]] && \
#[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
#[[ `ls checkpoints/${dependency_prefix}*.checkpoint |  wc -l` -eq $num_samples ]]
#do
#	date
#	printf "Waiting for resources to begin trimming.\n"
#	sleep 600
#done
#if [[ `checkpoints_exist $input_prefix` == "true" ]]
#then
#	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
#	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_samples ]]
#	then
#		date
#		printf "Error detected in ${input_prefix} checkpoint. \
#Restarting step.\n"
#		wipecheckpoints $input_prefix
#		trim_galore_jobid=`no_depend --array $array_size \
#${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir $trimmed_dir`
#	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
#	then
#		date
#		printf "${input_prefix} run already completed. Skipping.\n"
#	fi
#else
#	date
#	printf "Beginning ${input_prefix} step.\n"
#	wipecheckpoints $input_prefix
#	trim_galore_jobid=`no_depend --array $array_size \
#${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir $trimmed_dir`
#fi

## Run MultiQC on raw and trimmed read reports
## Depend start upon last job step
#dependency=$trim_galore_jobid
#dependency_prefix=$input_prefix
#input_sbatch=multiqc.sbatch
#input_prefix=`get_prefix $input_sbatch`
#if [[ $dependency ]]
#then
#	date
#	printf "Waiting for completion of $dependency to \
#start ${input_prefix} run.\n"
#	multiqc_jobid=`depend ${scripts_dir}${input_sbatch} $dependency \
#$qc_dir $scripts_dir`
#else
#	until [[ -f $samples_file ]] && \
#	[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
#	[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
#	do
#		date
#		printf "Waiting for completion of previous job steps to \
#start ${input_prefix} run.\n"
#		sleep 2700
#	done
#	if [[ `checkpoints_exist $input_prefix` == "true" ]]
#	then
#		date
#		printf "${input_prefix} run already completed. Skipping.\n"
#	else
#		date
#		printf "Beginning ${input_prefix} run.\n"
#		wipecheckpoints $input_prefix
#		multiqc_jobid=`no_depend ${scripts_dir}${input_sbatch} \
#$qc_dir $scripts_dir`
#	fi
#fi
#
## Remove original renamed reads to conserve memory  before next steps
## Keep same dependency
#if [[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
#[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
#then
#	if [[ -f checkpoints/og_reads_deleted.checkpoint  ]]
#	then
#		date
#		printf "Original reads already removed. Skipping.\n"
#	else	
#		date
#		printf "Removing original renamed reads to conserve \
#memory before next steps.\n"
#		for sample_id in `cat $samples_file`
#		do
#			if \
#[[ -f ${samples_dir}/${sample_id}_R1.fastq.gz ]] && \
#[[ -f ${samples_dir}/${sample_id}_R2.fastq.gz ]] && \
#[[ -f ${trimmed_dir}/${sample_id}_R1_val_1.fq.gz ]] && \
#[[ -f ${trimmed_dir}/${sample_id}_R2_val_2.fq.gz ]]
#			then
#				rm ${samples_dir}/${sample_id}_R1.fastq.gz
#				rm ${samples_dir}/${sample_id}_R2.fastq.gz
#			else
#				printf "Error - some reads missing \
#for ${sample_id}, and no checkpoint file for original read deletion \
#step detected.\n"
#				exit 1
#			fi
#		done
#		touch checkpoints/og_reads_deleted.checkpoint
#	fi
#fi
#
## Run HISAT2-build on genome
#input_sbatch=build_hisat2.sbatch
#input_prefix=`get_prefix $input_sbatch`
#if [[ `checkpoints_exist $input_prefix` == "true" ]]
#then
#	date
#	printf "${input_prefix} already run for genome:\n\
#${genome}.\n\
#Skipping.\n"
#else
#	date
#	printf "Running ${input_prefix} on \n\ ${genome}.\n\
#Find results in directory 'hisat2'.\n"
#	build_hisat2_jobid=`no_depend ${scripts_dir}${input_sbatch} $genome`
#fi
#
## Run HISAT2 on all samples
## Depend start upon last job step
#dependency_prefix=$input_prefix
#input_sbatch=hisat2.sbatch
#input_prefix=`get_prefix $input_sbatch`
#until [[ `checkpoints_exist $dependency_prefix` == "true" ]]
#do
#	date
#	printf "Waiting for completion of $dependency_prefix step.\n"
#	sleep 600
#done
#if [[ `checkpoints_exist $input_prefix` == "true" ]]
#then
#	date
#	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
#	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_samples ]]
#	then
#		date
#		printf "Error detected in ${input_prefix} checkpoint. \
#Restarting step.\n"
##		wipecheckpoints $input_prefix
##		hisat2_jobid=`no_depend --array $array_size \
##${scripts_dir}${input_sbatch} $genome $samples_file $trimmed_dir $qc_dir $indiv_file`
#	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
#	then
#		date
#		printf "${input_prefix} run already completed. Skipping.\n"
#	fi
#else
#	date
#	printf "Beginning ${input_prefix} step.\n"
##	wipecheckpoints $input_prefix
##	hisat2_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
##$genome $samples_file $trimmed_dir $qc_dir $indiv_file`
#fi

# Sort IDs in $indiv_file for unique invidual IDs
dependency_prefix=$input_prefix
until [[ -f $indiv_file ]] && \
[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
do
	{ date & printf "Waiting for completion of \
$dependency_prefix step.\n"; } >> $pipeline_log
	sleep 1200
done
if [[ -f $indiv_file ]]
then
	{ date & printf "Sorting $indiv_file for unique \
invidual IDs.\n"; } >> $pipeline_log
	sort -u $indiv_file > sorted_${indiv_file}
	mv sorted_${indiv_file} $indiv_file
else
	{ date & printf "Error - $indiv_file not \
detected.\n"; } >> $pipeline_log
	exit 1
fi

## Run GATK4 MarkDuplicates on all samples
## Keep same dependency
#dependency_prefix=$dependency_prefix
#input_sbatch=mark_dupes.sbatch
#input_prefix=`get_prefix $input_sbatch`
#until [[ -f $indiv_file ]] && \
#[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
#[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
#do
#	date
#	printf "Waiting for completion of $dependency_prefix step.\n"
#	sleep 1200
#done
#if [[ `checkpoints_exist $input_prefix` == "true" ]]
#then
#	date
#	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
#	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_samples ]]
#	then
#		date
#		printf "Error detected in ${input_prefix} checkpoint. \
#Restarting step.\n"
##		wipecheckpoints $input_prefix
##		mark_dupes_jobid=`no_depend --array $array_size \
##${scripts_dir}${input_sbatch} $genome $samples_file $qc_dir`
#	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
#	then
#		date
#		printf "${input_prefix} run already completed. Skipping.\n"
#	fi
#else
#	date
#	printf "Beginning ${input_prefix} step.\n"
##	wipecheckpoints $input_prefix
##	mark_dupes_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
##$genome $samples_file $qc_dir`
#fi

# Set new array size for BAM collapse & after = number of individuals
if [[ -f $indiv_file ]]
then
	num_indiv=`cat $indiv_file | wc -l`
	array_size=$num_indiv
	{ date & printf "Array size set to ${num_indiv}.\n"; } >> $pipeline_log
else
	{ date & printf "Error - $indiv_file not detected.\n"; } >> $pipeline_log
	exit 1
fi

## Collapse BAMs with GATK4 MergeSamFiles
## Depend start upon last job step
#dependency_prefix=$input_prefix
#input_sbatch=collapse_bams.sbatch
#input_prefix=`get_prefix $input_sbatch`
#until [[ -f $indiv_file ]] && \
#[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
#[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
#do
#	date
#	printf "Waiting for completion of $dependency_prefix step.\n"
#	sleep 3600
#done
#if [[ `checkpoints_exist $input_prefix` == "true" ]]
#then
#	date
#	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
#	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_indiv ]]
#	then
#		date
#		printf "Error detected in ${input_prefix} checkpoint. \
#Restarting step.\n"
##		wipecheckpoints $input_prefix
##		collapse_bams_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
##$genome $indiv_file`
#	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_indiv ]]
#	then
#		date
#		printf "${input_prefix} run already completed. Skipping.\n"
#	fi
#else
#	date
#	printf "Beginning ${input_prefix} step.\n"
##	wipecheckpoints $input_prefix
##	collapse_bams_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
##$genome $indiv_file`
#fi
#
# Run GATK4 HaplotypeCaller
# Depend start upon last job step
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}haplotype_caller.sbatch
input_prefix=`get_prefix $input_sbatch`
sleep_time=600
pipeliner --array $array_size $dependency_prefix $dependency_size \
$sleep_time $input_sbatch \
$genome $indiv_file /scratch/kdeweese/$gvcfs_dir
dependency_size=$array_size
#until [[ -f $indiv_file ]] && \
#[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
#[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_indiv ]]
#do
#	date
#	printf "Waiting for completion of $dependency_prefix step.\n"
#	sleep 3600
#done
#if [[ `checkpoints_exist $input_prefix` == "true" ]]
#then
#	date
#	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
#	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_indiv ]]
#	then
#		printf "Error detected in ${input_prefix} checkpoint. \
#Restarting step.\n"
#		wipecheckpoints $input_prefix
#		haplotype_caller_jobid=`no_depend --array $array_size \
#${scripts_dir}${input_sbatch} $genome $indiv_file`
#	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_indiv ]]
#	then
#		date
#		printf "${input_prefix} run already completed. Skipping.\n"
#	fi
#else
#	date
#	printf "Beginning ${input_prefix} step.\n"
#	wipecheckpoints $input_prefix
#	haplotype_caller_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
#$genome $indiv_file`
#fi
#
## Run GATK4 GenotypeGVCFs
## Depend start upon last job step
#dependency_prefix=$input_prefix
#input_sbatch=genotype_gvcfs.sbatch
#input_prefix=`get_prefix $input_sbatch`
#until [[ -f $indiv_file ]] && \
#[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
#[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_indiv ]]
#do
#	date
#	printf "Waiting for completion of $dependency_prefix step.\n"
#	sleep 3600
#done
#if [[ `checkpoints_exist $input_prefix` == "true" ]]
#then
#	date
#	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
#	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_indiv ]]
#	then
#		printf "Error detected in ${input_prefix} checkpoint. \
#Restarting step.\n"
#	wipecheckpoints $input_prefix
#	genotype_gvcfs_jobid=`no_depend --array $array_size \
#${scripts_dir}${input_sbatch} $genome $indiv_file`
#	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_indiv ]]
#	then
#		date
#		printf "${input_prefix} run already completed. Skipping.\n"
#	fi
#else
#	date
#	printf "Beginning ${input_prefix} step.\n"
#	wipecheckpoints $input_prefix
#	genotype_gvcfs_jobid=`no_depend --array $array_size \
#${scripts_dir}${input_sbatch} $genome $indiv_file`
#fi
