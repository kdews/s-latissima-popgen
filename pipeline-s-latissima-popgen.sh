#!/bin/bash
#SBATCH -p cegs
#SBATCH --time=4-0
#SBATCH -J queen
#SBATCH -o queen.log

## Saccharina latissima SNP calling pipeline
# A SLURM- and conda-dependent pipeline with sequential job
# steps linked by dependencies and checkpoint files

# Help message
if [[ $1 = "-h" ]] || [[ $1 = "--help" ]]
then
	printf "\
Takes as input a genome and path to directory containing (gzipped) \n\
FASTQ files, and outputs...\n\
 - wgs
	*fastq.gz - FASTQ copies renamed to succinct sample IDs\n\
	samples_file.txt - master file to index sample IDs\n\
 - quality_control
	*_fastqc.zip/html - FastQC reports for all input FASTQs\n\
	*_val_1/2_fastqc.zip/html - FASTQC reports for trimmed FASTQs\n\
	*_trimming_report.txt - Trim Galore! report\n\
	multiqc_report.html - MultiQC report summarizing raw & trimmed QCs\n\
 - trimmed_reads
	*_val_1/2.fq.gz - reads post quality and adapter trimming by Trim Galore!\n\
Usage: sh pipeline_template.sh\n\n\
Assumes SBATCH files will be named with convention \n\
<prefix>.sbatch (e.g., fastqc.sbatch).\n\
Log files will be saved to the directory <prefix>_logs, \n\
and named <prefix>_<sample_idx>.out \n"
	exit 0
fi


# Define global variables and functions
# User defined
genome=/project/noujdine_61/kdeweese/latissima/Assembly/Assembled_scaffolds__masked_/SlaSLCT1FG3_1_AssemblyScaffolds_Repeatmasked.fasta.gz
path_to_raw_reads=/project/noujdine_61/kdeweese/latissima/all_wgs_OG_names
user_id=`whoami`
partition="cegs"
# Optional, specifies directory containing scripts, MUST end in "/"
scripts_dir=s-latissima-popgen/ # don't set if you don't plan to use it
# Specific to pipeline
num_samples=`expr $(ls ${path_to_raw_reads}/*fastq.gz | wc -l) / 2`
samples_dir=wgs
samples_file=${samples_dir}/samples_file.txt
qc_dir=quality_control
trimmed_dir=trimmed_reads
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
		local sbatch_file=$2
		# Takes prefix of SBATCH file
		local prefix=`get_prefix $sbatch_file`
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable --array=1-${num_samples} -o ${logdir}/%x_%a.out \
$sbatch_file "${@:3}"`
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
		local sbatch_file=$2
		local dep_jobid=$3
		# Takes prefix of SBATCH file
		local prefix=`get_prefix $sbatch_file`
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable --array=1-${num_samples} -o ${logdir}/%x_%a.out \
--dependency=afterok:${dep_jobid} $sbatch_file "${@:4}"`
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

# Run pipeline
# Rename reads and create $samples_file
input_sbatch=rename.sbatch
input_prefix=`get_prefix $input_sbatch`
# Before running, check if run has already succeeded
if [[ `checkpoints_exist $input_prefix` == "true" ]] \
&& [[ -f $samples_file ]]
then
	date
	printf "Checkpoint and $samples_file detected. Skipping ${input_prefix} step.\n"
else
	echo `checkpoints_exist $input_prefix`
	wipecheckpoints $input_prefix
	date
	printf "Renaming: Files in $path_to_raw_reads copied \
into $samples_dir and renamed.\n"
	rename_jobid=`no_depend ${scripts_dir}${input_sbatch} \
$path_to_raw_reads $samples_dir $samples_file $scripts_dir`
fi

# FastQC
# Depend start upon last job step
dependency=$rename_jobid
dependency_prefix=$input_prefix
input_sbatch=fastqc.sbatch
input_prefix=`get_prefix $input_sbatch`
# Check for known dependency
if [[ $dependency ]]
then
	date
	printf "Running FastQC on raw reads in ${samples_dir} following \
completion of $dependency_prefix job (jobid $dependency).\n"
	fastqc_jobid=`depend --array \
${scripts_dir}/${input_sbatch} $dependency $samples_file \
$samples_dir $qc_dir`
# If dependency is finished running, verify its checkpoint and $samples_file
elif [[ -f $samples_file ]] && \
[[ `checkpoints_exist $dependency_prefix` == "true" ]]
then
	# Now check for any existing checkpoints for this step
	if [[ `checkpoints_exist $input_prefix` == "true" ]]
	then
		echo `checkpoints_exist $input_prefix`
		printf "Checkpoint detected for ${input_prefix}. Validating...\n"
		# If required number of checkpoints not met, erase existing
		if [[ `ls checkpoints/${input_prefix}*.checkpoint | \
wc -l` -ne $num_samples ]]
		then
			wipecheckpoints $input_prefix
			date
			printf "Eror detected in ${input_prefix} checkpoint. \
Rerunning ${input_prefix} on raw reads in ${samples_dir}.\n"
			fastqc_jobid=`no_depend --array \
${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir`
		elif [[ `ls checkpoints/${input_prefix}*.checkpoint | \
wc -l` == $num_samples ]]
		then
			date
			printf "${input_prefix} run already completed. Skipping.\n"
		fi
	else
		wipecheckpoints $input_prefix
		date
		printf "Running FastQC on raw reads in ${samples_dir}.\n"
		fastqc_jobid=`no_depend --array \
${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir`
	fi
else
	printf "Error - either $samples_file or \
dependency checkpoint are missing.\n"
	exit 1
fi

# Quality and adapter trimming
# Depend start upon last job step
dependency_prefix=$input_prefix
input_sbatch=trim_galore.sbatch
input_prefix=`get_prefix $input_sbatch`
until [[ -f $samples_file ]] && \
[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint |  wc -l` == $num_samples ]]
do
	date
	printf "Waiting for resources to begin trimming.\n"
	sleep 600
done
if [[ `checkpoints_exist $input_prefix` == "true" ]]
then
	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_samples ]]
	then
		date
		printf "Error detected in ${input_prefix} checkpoint. \
Restarting step.\n"
		wipecheckpoints $input_prefix
		trim_galore_jobid=`no_depend --array \
${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir`
	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` == $num_samples ]]
	then
		date
		printf "${input_prefix} run already completed. Skipping.\n"
	fi
else
	date
	printf "Beginning ${input_prefix} step.\n"
	wipecheckpoints $input_prefix
	trim_galore_jobid=`no_depend --array \
${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir $trimmed_dir`
fi

# Run MultiQC on raw and trimmed read reports
# Depend start upon last job step
dependency=$trim_galore_jobid
dependency_prefix=$input_prefix
input_sbatch=multiqc.sbatch
input_prefix=`get_prefix $input_sbatch`
if [[ $dependency ]]
then
	date
	printf "Waiting for completion of $dependency to \
start ${input_prefix} run.\n"
	multiqc_jobid=`depend ${scripts_dir}${input_sbatch} $dependency \
$qc_dir $scripts_dir`
else
	until [[ -f $samples_file ]] && \
	[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
	[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` == $num_samples ]]
	do
		date
		printf "Waiting for completion of previous job steps to \
	start ${input_prefix} run.\n"
		sleep 2700
	done
	if [[ `checkpoints_exist $input_prefix` == "true" ]]
	then
		date
		printf "${input_prefix} run already completed. Skipping.\n"
	else
		date
		printf "Beginning ${input_prefix} run.\n"
		wipecheckpoints $input_prefix
		multiqc_jobid=`no_depend ${scripts_dir}${input_sbatch} \
	$qc_dir $scripts_dir`
	fi
fi

# Run HISAT2-build on genome
# Keep previous dependency used by last job step
dependency=$dependency
dependency_prefix=$dependency_prefix
input_sbatch=hisat2_build.sbatch
input_prefix=`get_prefix $input_sbatch`
if [[ $dependency ]]
then
	date
	printf "Waiting for completion of $dependency to \
start ${input_prefix} run.\n"
	hisat2_build_jobid=`depend ${scripts_dir}${input_sbatch} \
$dependency $genome`
else
	until [[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
	[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` == $num_samples ]]
	do
		date
		printf "Waiting for completion of ${dependency_prefix} step.\n"
		sleep 2700
	done
	if [[ `checkpoints_exist $input_prefix` == "true" ]]
	then
		date
		printf "HISAT2-build already run for genome: ${genome}. Skipping.\n"
	else
		date
		printf "Running HISAT2-build on ${genome}. Find results in directory 'genome'.\n"
		hisat2_build_jobid=`no_depend ${scripts_dir}${input_sbatch} $genome`
	fi
fi

# Run HISAT2 on all samples
# Depend start upon last job step
dependency_prefix=$input_prefix
input_sbatch=hisat2.sbatch
input_prefix=`get_prefix $input_sbatch`
until [[ `checkpoints_exist $dependency_prefix` == "true" ]]
do
	date
	printf "Waiting for completion of $dependency_prefix step.\n"
	sleep 600
done
if [[ `checkpoints_exist $input_prefix` == "true" ]]
then
	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_samples ]]
	then
		date
		printf "Error detected in ${input_prefix} checkpoint. \
Restarting step.\n"
		wipecheckpoints $input_prefix
		hisat2_jobid=`no_depend --array \
${scripts_dir}${input_sbatch} $genome $samples_file $trimmed_dir`
	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` == $num_samples ]]
	then
		date
		printf "${input_prefix} run already completed. Skipping.\n"
	fi
else
	date
	printf "Beginning ${input_prefix} step.\n"
	wipecheckpoints $input_prefix
	hisat2_jobid=`no_depend --array \
${scripts_dir}${input_sbatch} $genome $samples_file $trimmed_dir`
fi
