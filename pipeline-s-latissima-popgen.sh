#!/bin/bash

## SEQUENTIAL SBATCH SUBMISSION
# A customizable template to create a pipeline 
# with multiple job steps linked by dependencies

# Help message
if [[ $1 = "-h" ]] || [[ $1 = "--help" ]]
then
	printf "\
Creates a 'samples_file' (text file containing a unique \n\
sample ID on each line that corresponds to all input file \n\
name prefixes) from a set of input samples, and runs a pipeline \n\
with options for dependencies on that set of samples.\n\n\
Usage: sh pipeline_template.sh\n\n\
Assumes SBATCH files will be named with convention \n\
<prefix>.sbatch (e.g., fastqc.sbatch).\n\
Log files will be saved to the directory <prefix>_logs, \n\
and named <prefix>_<sample_idx>.out \n"
	exit 0
fi


# Define global variables and functions
scripts_dir=s-latissima-popgen
path_to_raw_reads=/project/noujdine_61/kdeweese/latissima/all_wgs_OG_names
num_samples=380
samples_dir=wgs
samples_file=${samples_dir}/samples_file.txt
user_id=`whoami`
partition="cegs"
qc_dir=quality_control
# Define function for array or non-array submission
# that returns the jobid but takes no dependencies
no_depend () {
	# Define job type
	# Determine array size for all batch jobs
	# (e.g., number of samples)
	if [[ $1 == "--array" ]]
	then
		# Inputs
		local sbatch_file=$2
		# Takes prefix of SBATCH file
		local prefix=`basename $sbatch_file | sed 's/\..*//g'`
		local logdir=${prefix}_logs
		# Create log directory (if needed)
		if [[ ! -d $logdir ]]
		then
			mkdir $logdir
		fi
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable --array=1-${num_samples} -o ${logdir}/%x_%a.out \
$sbatch_file "${@:3}"`
	else
		# Inputs
		local sbatch_file=$1
		# Takes prefix of SBATCH file
		local prefix=`basename $sbatch_file | sed 's/\..*//g'`
		local logdir=${prefix}_logs
		# Create log directory (if needed)
		if [[ ! -d $logdir ]]
		then
			mkdir $logdir
		fi
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
		local sbatch_file=$2
		local dep_jobid=$3
		# Takes prefix of SBATCH file
		local prefix=`basename $sbatch_file | sed 's/\..*//g'`
		local logdir=${prefix}_logs
		# Create log directory (if needed)
		if [[ ! -d $logdir ]]
		then    
			mkdir $logdir
		fi
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable --array=1-${num_samples} -o ${logdir}/%x_%a.out \
--dependency=afterok:${dep_jobid} $sbatch_file "${@:4}"`
	else
		# Inputs
		local sbatch_file=$1
		local dep_jobid=$2
		# Takes prefix of SBATCH file
		local prefix=`basename $sbatch_file | sed 's/\..*//g'`
		local logdir=${prefix}_logs
		# Create log directory (if needed)
		if [[ ! -d $logdir ]]
		then    
			mkdir $logdir
		fi
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable -o ${logdir}/%x.out --dependency=afterok:${dep_jobid} \
$sbatch_file "${@:3}"`
	fi
	echo "$jobid"
}


# Run pipeline
# Rename reads and create $samples_file
# Before running, test if run has already succeeded
if [[ -f checkpoint/rename.checkpoint ]] && [[ -f $samples_file ]]
then
	printf "Renamed files have already been \
created successfully in ${samples_dir}.\n"
else
	printf "Renaming files in $path_to_raw_reads to \
${samples_dir}.\n"
	if [[ -f checkpoint/rename.checkpoint ]]
	then
		rm checkpoint/rename.checkpoint
	fi
	rename_jobid=`no_depend ${scripts_dir}/rename.sbatch \
$path_to_raw_reads $samples_dir $samples_file $scripts_dir`
fi


# FastQC
if [[ $rename_jobid ]]
then
	fastqc_jobid=`depend --array \
${scripts_dir}/fastqc.sbatch $rename_jobid $samples_file \
$samples_dir $qc_dir`
elif [[ -f $samples_file ]] && [[ -f checkpoint/rename.checkpoint ]]
then
	if [[ `ls checkpoint/fastqc*.checkpoint | wc -l` -ne $num_samples ]]
	then
		rm checkpoint/fastqc*.checkpoint
		fastqc_jobid=`no_depend --array \
${scripts_dir}/fastqc.sbatch $samples_file $samples_dir $qc_dir`
	elif [[ `ls checkpoint/fastqc.checkpoint | wc -l` == $num_samples ]]
	then
		continue
	fi
else
	printf "Error - either $samples_file or \
checkpoint/rename.checkpoint are missing.\n"
	exit 1
fi


## Quality and adapter trimming
#if [[ $rename_jobid ]]
#then
#	trim_galore_jobid=`depend --array \
#${scripts_dir}/trim_galore.sbatch $rename_jobid $samples_file \
#$samples_dir $qc_dir`
#elif [[ -f $samples_file ]] && [[ -f checkpoint/rename.checkpoint ]]
#then
#	if [[ `ls checkpoint/trim_galore*.checkpoint | wc -l` -ne $num_samples ]]
#	then
#		rm checkpoint/trim_galore*.checkpoint
#		trim_galore_jobid=`no_depend --array \
#${scripts_dir}/trim_galore.sbatch $samples_file $samples_dir $qc_dir`
#	elif [[ `ls checkpoint/trim_galore*.checkpoint | wc -l` == $num_samples ]]
#	then
#		continue
#	fi
#else
#	printf "Error - either $samples_file or \
#checkpoint/rename.checkpoint are missing.\n"
#        exit 1
#fi
#
## Run MultiQC on raw and trimmed read reports
#if [[ $fastqc_jobid ]] || [[ $trim_galore_jobid ]]
#then
#	rm checkpoint/multiqc*.checkpoint
#	multiqc_jobid=`depend ${scripts_dir}/multiqc.sbatch \
#$trim_galore_jobid $qc_dir $scripts_dir`
#elif [[ -f $samples_file ]] && [[ -f checkpoint/rename.checkpoint ]]
#then
#	if [[ `ls checkpoint/multiqc*.checkpoint | wc -l` -ne $num_samples ]]
#	then
#		rm checkpoint/multiqc*.checkpoint
#		multiqc_jobid=`no_depend ${scripts_dir}/multiqc.sbatch \
#$qc_dir $scripts_dir`
#	elif [[ `ls checkpoint/multiqc*.checkpoint | wc -l` == $num_samples ]]
#	then
#		continue
#	fi
#else
#	printf "Error - either $samples_file or \
#checkpoint/rename.checkpoint are missing.\n"
#	exit 1
#fi
#
