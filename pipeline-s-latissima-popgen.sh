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
 - wgs/\n\
	*fastq.gz - FASTQ copies renamed to succinct sample IDs\n\
	samples_file.txt - master file to index sample IDs\n\
 - quality_control/\n\
	*_fastqc.zip/html - FastQC reports for all input FASTQs\n\
	*_val_1/2_fastqc.zip/html - FASTQC reports for trimmed FASTQs\n\
	*_trimming_report.txt - Trim Galore! report\n\
	*.hisat2.summary - HISAT2 report\n\
	multiqc_report.html - MultiQC report summarizing QCs at each step\n\
 - trimmed_reads/\n\
	*_val_1/2.fq.gz - reads post quality and adapter trimming by Trim Galore!\n\
 - hisat2/\n\
	*.ht2 - indexed genome\n\
	*sorted.bam - sorted alignment files of trimmed reads to genome\n\
 - individuals_file.txt\n\
	master file to index individual IDs\n\
 - mark_dupes\n\
	*sorted.marked.bam - sorted alignment files with duplicates marked\n\
 - collapsed_bams\n\
	*sorted.marked.merged.bam - sorted alignment files merged by individual\n\
 - gvcfs\n\
	*.g.vcf.gz - genome variant call files (gVCFs) for each individual\n\
 - genotyped_vcfs\n\
	*vcf.gz - variant call files (VCFs) for each individual\n\
 - *_logs/\n\
	*.log - SLRUM log files from inividual job step submissions\n\
 - checkpoints/\n\
	*.checkpoint - checkpoint file(s) for job step, created upon job completion\n\
Usage: sh pipeline_template.sh\n\n\
Assumes SBATCH files will be named with convention \n\
<prefix>.sbatch (e.g., fastqc.sbatch).\n\
Log files will be saved to the directory <prefix>_logs,\n\
and named <prefix>_<sample_idx>.out\n"
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
indiv_file=individuals_file.txt
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
		local sbatch_file=$3
		# Takes prefix of SBATCH file
		local prefix=`get_prefix $sbatch_file`
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable --array=1-${array_size} -o ${logdir}/%x_%a.out \
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
		local sbatch_file=$3
		local dep_jobid=$4
		# Takes prefix of SBATCH file
		local prefix=`get_prefix $sbatch_file`
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
		local jobid=`sbatch -p $partition -J ${prefix} \
--parsable --array=1-${array_size} -o ${logdir}/%x_%a.out \
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

# Run pipeline
# Set array size for working with sample IDs
array_size=$num_samples
date
printf "Array size set to ${num_samples}.\n"

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
	fastqc_jobid=`depend --array $array_size \
${scripts_dir}/${input_sbatch} $dependency $samples_file \
$samples_dir $qc_dir`
# If dependency is finished running, verify its checkpoint and $samples_file
elif [[ -f $samples_file ]] && \
[[ `checkpoints_exist $dependency_prefix` == "true" ]]
then
	# Now check for any existing checkpoints for this step
	if [[ `checkpoints_exist $input_prefix` == "true" ]]
	then
		printf "Checkpoint detected for ${input_prefix}. Validating...\n"
		# If required number of checkpoints not met, erase existing
		if [[ `ls checkpoints/${input_prefix}*.checkpoint | \
wc -l` -ne $num_samples ]]
		then
			wipecheckpoints $input_prefix
			date
			printf "Eror detected in ${input_prefix} checkpoint. \
Rerunning ${input_prefix} on raw reads in ${samples_dir}.\n"
			fastqc_jobid=`no_depend --array $array_size \
${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir`
		elif [[ `ls checkpoints/${input_prefix}*.checkpoint | \
wc -l` -eq $num_samples ]]
		then
			date
			printf "${input_prefix} run already completed. Skipping.\n"
		fi
	else
		wipecheckpoints $input_prefix
		date
		printf "Running FastQC on raw reads in ${samples_dir}.\n"
		fastqc_jobid=`no_depend --array $array_size \
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
[[ `ls checkpoints/${dependency_prefix}*.checkpoint |  wc -l` -eq $num_samples ]]
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
		trim_galore_jobid=`no_depend --array $array_size \
${scripts_dir}${input_sbatch} $samples_file $samples_dir $qc_dir $trimmed_dir`
	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
	then
		date
		printf "${input_prefix} run already completed. Skipping.\n"
	fi
else
	date
	printf "Beginning ${input_prefix} step.\n"
	wipecheckpoints $input_prefix
	trim_galore_jobid=`no_depend --array $array_size \
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
	[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
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

# Remove original renamed reads to conserve memory  before next steps
# Keep same dependency
if [[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
then
	if [[ -f checkpoints/og_reads_deleted.checkpoint  ]]
	then
		date
		printf "Original reads already removed. Skipping.\n"
	else	
		date
		printf "Removing original renamed reads to conserve \
memory before next steps.\n"
		for sample_id in `cat $samples_file`
		do
			if \
[[ -f ${samples_dir}/${sample_id}_R1.fastq.gz ]] && \
[[ -f ${samples_dir}/${sample_id}_R2.fastq.gz ]] && \
[[ -f ${trimmed_dir}/${sample_id}_R1_val_1.fq.gz ]] && \
[[ -f ${trimmed_dir}/${sample_id}_R2_val_2.fq.gz ]]
			then
				rm ${samples_dir}/${sample_id}_R1.fastq.gz
				rm ${samples_dir}/${sample_id}_R2.fastq.gz
			else
				printf "Error - some reads missing \
for ${sample_id}, and no checkpoint file for original read deletion \
step detected.\n"
				exit 1
			fi
		done
		touch checkpoints/og_reads_deleted.checkpoint
	fi
fi

# Run HISAT2-build on genome
input_sbatch=build_hisat2.sbatch
input_prefix=`get_prefix $input_sbatch`
if [[ `checkpoints_exist $input_prefix` == "true" ]]
then
	date
	printf "${input_prefix} already run for genome:\n\
${genome}.\n\
Skipping.\n"
else
	date
	printf "Running ${input_prefix} on \n\ ${genome}.\n\
Find results in directory 'hisat2'.\n"
	build_hisat2_jobid=`no_depend ${scripts_dir}${input_sbatch} $genome`
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
	date
	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_samples ]]
	then
		date
		printf "Error detected in ${input_prefix} checkpoint. \
Restarting step.\n"
		wipecheckpoints $input_prefix
#		hisat2_jobid=`no_depend --array $array_size \
#${scripts_dir}${input_sbatch} $genome $samples_file $trimmed_dir $qc_dir $indiv_file`
	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
	then
		date
		printf "${input_prefix} run already completed. Skipping.\n"
	fi
else
	date
	printf "Beginning ${input_prefix} step.\n"
	wipecheckpoints $input_prefix
#	hisat2_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
#$genome $samples_file $trimmed_dir $qc_dir $indiv_file`
fi

# Sort IDs in $indiv_file for unique invidual IDs
dependency_prefix=$input_prefix
until [[ -f $indiv_file ]] && \
[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
do
	date
	printf "Waiting for completion of $dependency_prefix step.\n"
	sleep 1200
done
if [[ -f $indiv_file ]]
then
	date
	printf "Sorting $indiv_file for unique invidual IDs.\n"
	sort -u $indiv_file > sorted_${indiv_file}
	mv sorted_${indiv_file} $indiv_file
else
	date
	printf "Error - $indiv_file not detected.\n"
	exit 1
fi

# Run GATK4 MarkDuplicates on all samples
# Keep same dependency
dependency_prefix=$dependency_prefix
input_sbatch=mark_dupes.sbatch
input_prefix=`get_prefix $input_sbatch`
until [[ -f $indiv_file ]] && \
[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
do
	date
	printf "Waiting for completion of $dependency_prefix step.\n"
	sleep 1200
done
if [[ `checkpoints_exist $input_prefix` == "true" ]]
then
	date
	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_samples ]]
	then
		date
#		printf "Error detected in ${input_prefix} checkpoint. \
#Restarting step.\n"
		wipecheckpoints $input_prefix
		mark_dupes_jobid=`no_depend --array $array_size \
${scripts_dir}${input_sbatch} $genome $samples_file $qc_dir`
	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
	then
		date
		printf "${input_prefix} run already completed. Skipping.\n"
	fi
else
	date
	printf "Beginning ${input_prefix} step.\n"
	wipecheckpoints $input_prefix
#	mark_dupes_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
#$genome $samples_file $qc_dir`
fi

# Set new array size for BAM collapse & after = number of individuals
if [[ -f $indiv_file ]]
then
	num_indiv=`cat $indiv_file | wc -l`
	array_size=$num_indiv
	date
	printf "Array size set to ${num_indiv}.\n"
else
	date
	printf "Error - $indiv_file not detected.\n"
	exit 1
fi

# Collapse BAMs with GATK4 MergeSamFiles
# Depend start upon last job step
dependency_prefix=$input_prefix
input_sbatch=collapse_bams.sbatch
input_prefix=`get_prefix $input_sbatch`
until [[ -f $indiv_file ]] && \
[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_samples ]]
do
	date
	printf "Waiting for completion of $dependency_prefix step.\n"
	sleep 3600
done
if [[ `checkpoints_exist $input_prefix` == "true" ]]
then
	date
	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_indiv ]]
	then
		date
		printf "Error detected in ${input_prefix} checkpoint. \
Restarting step.\n"
		wipecheckpoints $input_prefix
		collapse_bams_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
$genome $indiv_file`
	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_indiv ]]
	then
		date
		printf "${input_prefix} run already completed. Skipping.\n"
	fi
else
	date
	printf "Beginning ${input_prefix} step.\n"
	wipecheckpoints $input_prefix
	collapse_bams_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
$genome $indiv_file`
fi

# Run GATK4 HaplotypeCaller
# Depend start upon last job step
dependency_prefix=$input_prefix
input_sbatch=haplotype_caller.sbatch
input_prefix=`get_prefix $input_sbatch`
until [[ -f $indiv_file ]] && \
[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq $num_indiv ]]
do
	date
	printf "Waiting for completion of $dependency_prefix step.\n"
	sleep 3600
done
if [[ `checkpoints_exist $input_prefix` == "true" ]]
then
	date
	printf "Checkpoint detected for ${input_prefix}. Validating...\n"
	if [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -ne $num_indiv ]]
	then
		printf "Error detected in ${input_prefix} checkpoint. \
Restarting step.\n"
		wipecheckpoints $input_prefix
		collapse_bams_jobid=`no_depend --array $array_size \
${scripts_dir}${input_sbatch} $genome $indiv_file`
	elif [[ `ls checkpoints/${input_prefix}*.checkpoint | wc -l` -eq $num_indiv ]]
	then
		date
		printf "${input_prefix} run already completed. Skipping.\n"
	fi
else
	date
	printf "Beginning ${input_prefix} step.\n"
	wipecheckpoints $input_prefix
	collapse_bams_jobid=`no_depend --array $array_size ${scripts_dir}${input_sbatch} \
$genome $indiv_file`
fi

