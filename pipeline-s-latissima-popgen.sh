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
Takes as input a genome and path to directory containing (gzipped)
FASTQ files, and outputs...
 - individuals_file.txt - master file to index individual IDs
 - wgs/
	*.fastq.gz - FASTQ copies renamed to succinct sample IDs
	*.repaired.fastq.gz - FASTQ read pairs repaired with repair.sh
	samples_file.txt - master file to index sample IDs
 - trimmed_reads/
	*_val_1/2.fq.gz - reads post quality and adapter trimming by Trim Galore!
 - bams/
	*.ht2 - indexed genome
	*sorted.bam - sorted alignment files of trimmed reads to genome
	*sorted.marked.bam - sorted alignment files with duplicates marked
	*sorted.marked.merged.bam - sorted alignment files merged by individual
 - indiv_gvcfs/
	*.g.vcf.gz - genome variant call files (gVCFs) for each individual
 - interval_gvcfs/
	*.g.vcf.gz - genome variant call files (gVCFs) for each genomic interval
 - vcfs/
	*vcf.gz - variant call files (VCFs) for each genomic interval
 - quality_control/
	*_fastqc.zip/html - FastQC reports for all input FASTQs
	*_val_1/2_fastqc.zip/html - FASTQC reports for trimmed FASTQs
	*_trimming_report.txt - Trim Galore! report
	*.hisat2.summary - HISAT2 report
	multiqc_report.html - MultiQC report summarizing QCs at each step
 - *_logs/
	*.log - SLRUM log files from inividual job step submissions
 - checkpoints/
	*.checkpoint - checkpoint file(s) for each job step, created 
                       upon job completion
	               the number of checkpoint files corresponds to 
                       the array size of that job step

Usage: sh pipeline_template.sh

Assumes SBATCH files will be named with convention: \
<prefix>.sbatch (e.g., fastqc.sbatch).
Log files will be saved to the directory <prefix>_logs,
and named <prefix>_<array_idx>.out\n"
	exit 0
fi


# Define global variables and functions
# User defined
partition=cegs
pipeline_log=queen.log
#outdir="" # Optional, specficies output directory for entire pipeline
scripts_dir=s-latissima-popgen # Optional, specifies directory containing scripts
genome=/project/noujdine_61/kdeweese/latissima/Assembly/Assembled_scaffolds__masked_/SlaSLCT1FG3_1_AssemblyScaffolds_Repeatmasked.fasta.gz
path_to_raw_reads=/project/noujdine_61/kdeweese/latissima/all_wgs_OG_names
# If genome file exists, change name to realpath
[[ $genome ]] && genome=$(realpath $genome) && [[ -f $genome ]] || \
{ echo "Genome file $genome not detected." >> $pipeline_log; exit 1; }
genome_basename=$(basename -- $genome)
genome_basename_unzip=`echo $genome_basename | sed 's/\.gz//g'`
genome_base=`echo $genome_basename | sed 's/\..*//g'`
# If path to raw reads exists, change name to realpath
[[ $path_to_raw_reads ]] && path_to_raw_reads=$(realpath $path_to_raw_reads) && \
[[ -d $path_to_raw_reads ]] || { echo "Reads directory $path_to_raw_reads \
not detected." >> $pipeline_log; exit 1; }
# If scripts directory is speicified and exists, 
# change to realpath & append '/' to name
if [[ $scripts_dir ]]
then
	[[ -d $scripts_dir ]] && echo "Searching for scripts in \
${scripts_dir}..." >> $pipeline_log && scripts_dir=$scripts_dir/ \
|| echo "Searching for scripts in current directory: `pwd`..." >> $pipeline_log
fi
# If output directory is specified and exists, change to directory
if [[ $outdir ]]
then 
	[[ -d $outdir ]] && cd $outdir && [[ $? -eq 0 ]] && \
echo "Writing all output to ${outdir}." >> $pipeline_log || \
{ echo "Error - output directory ${outdir} doesn't exist. Exiting." >> \
$pipeline_log; exit 1; }
fi
# Specific to pipeline
num_samples=`expr $(ls ${path_to_raw_reads}/*fastq.gz | wc -l) / 2`
samples_dir=wgs
samples_file=${samples_dir}/samples_file.txt
indiv_file=individuals_file.txt
qc_dir=quality_control
trimmed_dir=trimmed_reads
bams_dir=bams
indiv_gvcfs_dir=indiv_gvcfs
split_intervals_dir=split_intervals
scatter=100 # number of interval chunks to make for scatter-gather parallelization
interval_gvcfs_dir=interval_gvcfs
vcfs_dir=vcfs
# Define function to format output file with newlines between job steps
printspace () {
	printf "\n" >> $pipeline_log
}
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
		local prefix=$4
		local trailing_args="${@:5}"
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
#		local jobid=`sbatch -p $partition -J ${prefix} \
#--parsable --array=${array_size} -o ${logdir}/%x_%a.out \
#$sbatch_file $prefix $trailing_args`
		echo "sbatch -p $partition -J ${prefix} \
--parsable --array=${array_size} -o ${logdir}/%x_%a.out \
$sbatch_file $prefix $trailing_args" >> $pipeline_log
	else
		# Inputs
		local sbatch_file=$1
		local prefix=$2
		local trailing_args="${@:3}"
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
#		local jobid=`sbatch -p $partition -J ${prefix} \
#--parsable -o ${logdir}/%x.out $sbatch_file $prefix $trailing_args`
		echo "sbatch -p $partition -J ${prefix} \
--parsable -o ${logdir}/%x.out $sbatch_file $prefix $trailing_args" \
>> $pipeline_log
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
		local prefix=$4
		local dep_jobid=$5
		local trailing_args="${@:6}"
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
#		local jobid=`sbatch -p $partition -J ${prefix} \
#--parsable --array=${array_size} -o ${logdir}/%x_%a.out \
#--dependency=afterok:${dep_jobid} $sbatch_file $prefix $trailing_args`
		echo "sbatch -p $partition -J ${prefix} \
--parsable --array=${array_size} -o ${logdir}/%x_%a.out \
--dependency=afterok:${dep_jobid} $sbatch_file $prefix $trailing_args" \
>> $pipeline_log
	else
		# Inputs
		local sbatch_file=$1
		local preifx=$2
		local dep_jobid=$3
		local trailing_args="${@:4}"
		# Create log directory named after prefix
		local logdir=`make_logdir $prefix`
		# Job submission
#		local jobid=`sbatch -p $partition -J ${prefix} \
#--parsable -o ${logdir}/%x.out --dependency=afterok:${dep_jobid} \
#$sbatch_file $prefix $trailing_args`
		echo "sbatch -p $partition -J ${prefix} \
--parsable -o ${logdir}/%x.out --dependency=afterok:${dep_jobid} \
$sbatch_file $prefix $trailing_args" >> $pipeline_log
	fi
	echo "$jobid"
}
# Define function to check for existence of a set of 
# similarly named checkpoint files with a wildcard
checkpoints_exist () {
	prefix=$1
	if [[ -z $prefix ]]
	then
		{ date;  echo "Error - no prefix supplied to \
checkpoints_exist function."; } >> $pipeline_log
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
		local input_prefix=$7
		local trailing_args="${@:8}"
	else
		local dependency_prefix=$1
		local dependency_size=$2
		local sleep_time=$3
		local input_sbatch=$4
		local input_prefix=$5
		local trailing_args="${@:6}"
	fi
	[[ "$@" ]] || { echo "Error - no input to pipeliner. \
Exiting..." >> $pipeline_log ; exit 1; }
	echo "pipeliner $@" >> $pipeline_log
	until [[ `checkpoints_exist $dependency_prefix` = "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | wc -l` -eq \
$dependency_size ]]
	do
		{ date; echo "Waiting for completion of \
$dependency_prefix step."; } >> $pipeline_log
		sleep $sleep_time
	done
	if [[ `checkpoints_exist $input_prefix` = "true" ]]
	then
		local num_checks=`ls \
checkpoints/${input_prefix}*.checkpoint | wc -l`
		{ date; echo "${num_checks} checkpoint(s) detected \
for ${input_prefix}. Validating..."; } >> $pipeline_log
		if [[ $1 = "--array" ]] && [[ $array_indices ]] && \
[[ $num_checks -ne $array_indices ]] 
		then
			local array_flag="${1} `missingcheckpoints \
$input_prefix $array_indices`"
		echo "Error detected in ${input_prefix} checkpoint. \
Restarting step at checkpoint." >> $pipeline_log
		echo "Submitting job array indices: $array_indices" \
>> $pipeline_log
		local jobid=`no_depend $array_flag $input_sbatch \
$input_prefix $trailing_args`
		elif [[ $num_checks -eq $array_indices ]]
		then
			echo "${input_prefix} run already \
completed. Skipping." >> $pipeline_log
		elif [[ $1 != "--array" ]] && [[ $num_checks -eq 1 ]]
		then
			echo "${input_prefix} run already \
completed. Skipping." >> $pipeline_log
		else
			echo "Error - check inputs to \
'pipeliner'." >> $pipeline_log
		fi
	else
		[[ $1 = "--array" ]] && [[ $array_indices ]] && \
local array_flag="${1} ${array_indices}"
		echo "Beginning ${input_prefix} step." \
>> $pipeline_log
		local jobid=`no_depend $array_flag $input_sbatch \
$input_prefix $trailing_args`
	fi
	echo $jobid
}


# Run pipeline
# Set array size for working with sample IDs
array_size=$num_samples
{ date; echo "Array size set to ${array_size}."; } >> $pipeline_log
printspace

# Set sleep time (wait time) between checking for checkpoints
sleep_time=1800
if (( $(( $sleep_time / 60 )) < 1 ))
then
	st="$(( $sleep_time / 60 )) second(s)"
elif (( $(( $sleep_time / 3600 )) > 1 ))
then
	hr="$(( $sleep_time / 3660 ))"
	min="$(( ($sleep_time - ($hr * 3600)) / 60 ))"
	st="$hr hour(s) and $min minute(s)"
else
	st="$(( $sleep_time / 60 )) minute(s)"
fi
{ date; echo "Wait time between checking for checkpoints \
set to: $st"; } >> $pipeline_log
printspace

# Rename reads and create $samples_file
input_sbatch=${scripts_dir}rename.sbatch
input_prefix=`get_prefix $input_sbatch`
# Before running, check if run has already succeeded
if [[ -f $samples_file ]] && \
[[ `checkpoints_exist $input_prefix` == "true" ]]
then
	{ date; echo "Checkpoint and $samples_file detected. \
Skipping ${input_prefix} step."; } >> $pipeline_log
else
	wipecheckpoints $input_prefix
	{ date; echo "Renaming: Files in $path_to_raw_reads \
copied into $samples_dir and renamed."; } >> $pipeline_log 
	jobid=`no_depend $input_sbatch $input_prefix \
$path_to_raw_reads $samples_dir $samples_file $scripts_dir`
fi
# Set dependency size for next step
dependency_size=1
printspace

# Repair FASTQs with BBMap repair.sh
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}repair.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$samples_dir $samples_dir \
$samples_file`
# Set dependency size for next step
dependency_size=$array_size
printspace

# Remove original renamed reads to conserve memory before next steps
# Depend start upon last job step
dependency_prefix=$input_prefix
input_prefix=og_reads_deleted
if [[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | \
wc -l` -eq $dependency_size ]]
then
	if [[ `checkpoints_exist $input_prefix` = "true" ]]
	then
		{ date; echo "Original reads already removed. \
Skipping."; } >> $pipeline_log
	else	
		{ date; echo "Removing original renamed reads \
to conserve memory before next steps."; } >> $pipeline_log
		for sample_id in `cat $samples_file`
		do
			if \
[[ -f ${samples_dir}/${sample_id}_R1.fastq.gz ]] && \
[[ -f ${samples_dir}/${sample_id}_R2.fastq.gz ]] && \
[[ -f ${trimmed_dir}/${sample_id}_R1.repaired.fastq.gz ]] && \
[[ -f ${trimmed_dir}/${sample_id}_R2.repaired.fastq.gz ]]
			then
				rm ${samples_dir}/${sample_id}_R1.fastq.gz
				rm ${samples_dir}/${sample_id}_R2.fastq.gz
			else
				{ date; echo "Error - some reads missing \
for ${sample_id}, and no checkpoint file detected for $input_prefix \
step."; } >> $pipeline_log
				exit 1
			fi
		done
		touch checkpoints/${input_prefix}.checkpoint
	fi
fi
printspace

# FastQC
# Keep previous dependency
dependency=$jobid
dependency_prefix=$dependency_prefix
input_sbatch=${scripts_dir}fastqc.sbatch
input_prefix=`get_prefix $input_sbatch`
# Check for dependency jobid
if [[ $dependency ]]
then
	{ date; echo "Running $input_prefix following completion of \
$dependency_prefix step (jobid ${dependency})."; } >> $pipeline_log
	jobid=`depend --array $array_size \
$input_sbatch $input_prefix $dependency \
$samples_dir $qc_dir \
$samples_file`
else
	# If dependency is finished running, verify its checkpoint
	jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$samples_dir $qc_dir \
$samples_file`
fi
# Set dependency size for next step
dependency_size=$array_size
printspace

# Quality and adapter trimming
# Depend start upon last job step
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}trim_galore.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$samples_dir $qc_dir \
$samples_file $trimmed_dir`
# Set dependency size for next step
dependency_size=$array_size
printspace

# Run HISAT2-build on genome
# Depend start upon last job step
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}build_hisat2.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$bams_dir $bams_dir \
$genome`
dependency_size=1
printspace

# Redefine $genome location after HISAT2-build step
if [[ -f ${bams_dir}/${genome_basename_unzip} ]]
then
	genome=${bams_dir}/${genome_basename_unzip}
	{ date; echo "Genome now being sourced from: $genome"; } >> $pipeline_log
else
	echo "Error - gunzipped genome not detected in ${bams_dir}."
	exit 1
fi
printspace

# Run HISAT2 on all samples
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}hisat2.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$trimmed_dir $bams_dir \
$genome $samples_file $qc_dir $indiv_file`
dependency_size=$array_size
# Set dependency size for next step
dependency_size=$array_size
printspace

# Sort IDs in $indiv_file for unique invidual IDs
dependency_prefix=$input_prefix
until [[ -f $indiv_file ]] && \
[[ `checkpoints_exist $dependency_prefix` == "true" ]] && \
[[ `ls checkpoints/${dependency_prefix}*.checkpoint | \
wc -l` -eq $dependency_size ]]
do
	{ date; echo "Waiting for completion of \
$dependency_prefix step."; } >> $pipeline_log
	sleep $sleep_time
done
if [[ -f $indiv_file ]]
then
	{ date; echo "Sorting $indiv_file for unique \
invidual IDs."; } >> $pipeline_log
	sort -u $indiv_file > sorted_${indiv_file}
	mv sorted_${indiv_file} $indiv_file
else
	{ date; echo "Error - $indiv_file not \
detected."; } >> $pipeline_log
	exit 1
fi
printspace

# Create reference genome dictionary and 
# samtools index of genome for GATK tools
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}prep_ref.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner $dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$bams_dir $bams_dir \
$genome`
# Set dependency size for next step
dependency_size=1
printspace

# Run GATK4 ValidateSamFile on HISAT2 alignmnet BAMs
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}validate_sams.sbatch
input_prefix=`get_prefix $input_sbatch`
pattern=.sorted.bam
iteration=1
input_prefix=${input_prefix}_${iteration}
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$bams_dir $qc_dir \
$genome $samples_file $pattern`
# Set dependency size for next step
dependency_size=$array_size
printspace

# Run GATK4 CollectAlignmentSummaryMetrics 
# on HISAT2 alignmnet BAMs
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}collect_alignment_summary_metrics.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$bams_dir $qc_dir \
$genome $samples_file`
# Set dependency size for next step
dependency_size=$array_size
printspace

## Run GATK4 CollectWgsMetrics on HISAT2 alignmnet BAMs
## Depend start upon last job step
#dependency=$jobid
#dependency_prefix=$input_prefix
#input_sbatch=${scripts_dir}collect_wgs_metrics.sbatch
#input_prefix=`get_prefix $input_sbatch`
#jobid=`pipeliner --array $array_size \
#$dependency_prefix $dependency_size \
#$sleep_time $input_sbatch $input_prefix \
#$bams_dir $qc_dir \
#$genome $samples_file`

# Run GATK4 MarkDuplicates
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}mark_dupes.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch \
$bams_dir $bams_dir \
$genome $samples_file $qc_dir`
# Set dependency size for next step
dependency_size=$array_size
printspace 

# Run GATK4 ValidateSamFile on MarkDuplicate BAMs
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}validate_sams.sbatch
input_prefix=`get_prefix $input_sbatch`
pattern=.marked.sorted.bam
iteration=2
input_prefix=${input_prefix}_${iteration}
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$bams_dir $qc_dir \
$genome $samples_file $pattern`
# Set dependency size for next step
dependency_size=$array_size
printspace

# Set new array size to number of individuals
if [[ -f $indiv_file ]]
then
	num_indiv=`cat $indiv_file | wc -l`
	array_size=$num_indiv
	{ date; echo "Array size set to ${array_size}."; } \
>> $pipeline_log
else
	{ date; echo "Error - $indiv_file not detected."; } \
>> $pipeline_log
	exit 1
fi
printspace

# Collapse BAMs per sample into BAMs per
# individual with GATK4 MergeSamFiles
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}collapse_bams.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$bams_dir $bams_dir \
$genome $indiv_file`
# Set dependency size for next step
dependency_size=$array_size
printspace

# Run GATK4 ValidateSamFile on MarkDuplicate BAMs
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}validate_sams.sbatch
input_prefix=`get_prefix $input_sbatch`
pattern=.merged.marked.sorted.bam
iteration=3
input_prefix=${input_prefix}_${iteration}
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$bams_dir $qc_dir \
$genome $indiv_file $pattern`
# Set dependency size for next step
dependency_size=$array_size
printspace

# Index collapsed BAMs for GATK HaplotypeCaller
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}index_bams.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$bams_dir $bams_dir \
$genome $indiv_file`
# Set dependency size for next step
dependency_size=$array_size
printspace

# Run GATK4 HaplotypeCaller
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}haplotype_caller.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$bams_dir $indiv_gvcfs_dir \
$genome $indiv_file`
# Set dependency size for next step
dependency_size=$array_size
printspace

# Run GATK4 SplitIntervals on genome to produce interval 
# lists in $split_intervals_dir for CombineGVCFs step
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}split_intervals.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner $dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$split_intervals_dir $split_intervals_dir \
$genome $scatter`

# Set new array size to expected number of expected output 
# combined gVCFs (i.e., = $scatter)
array_size=$scatter
#if [[ -f $genome ]]
#then
#	{ date; echo "Creating intervals file $intervals_file \
#from $genome chromosome/scaffold IDs.";} \
#>> $pipeline_log
#	intervals_file=`grep ">" $genome | sed 's/>//g'`
#else
#	{ date; echo "Genome file $genome not found. Exiting...";} \
#>> $pipeline_log
#	exit 1
#fi
#if [[ -f $intervals_file ]]
#then
#	num_intervals=`cat $intervals_file | wc -l`
#	array_size=$(( $num_intervals / $int_per_gvcf ))
#	{ date; echo "Array size set to ${array_size}."; } \
#>> $pipeline_log
#	{ date; echo "Chunking $intervals_file into $array_size \
#pieces in the directory ${interval_chunk_dir}..."; } >> $pipeline_log
#	[[ -d $interval_chunk_dir ]] || mkdir $interval_chunk_dir
#	chunk=1
#	for i in `seq $int_per_gvcf $int_per_gvcf $num_intervals`
#	do
#		head -n${i} $intervals_file | tail -n${int_per_gvcf} > \
#${interval_chunk_dir}/${chunk}_${intervals_file}
#		((++chunk))
#	done
#	[[ -d ${interval_chunk_dir} ]] && \
#[[ `ls ${interval_chunk_dir} | wc -l` -eq $array_size ]] && \
#[[ `cat ${interval_chunk_dir}/* | sort` = \
#`cat ${intervals_file} | sort` ]] && \
#echo "Chunking successful." >> $pipeline_log || \
#{ echo "Error - contents of ${interval_chunk_dir} files \
#=/= ${intervals_file}." >> $pipeline_log; exit 1; }
#else
#        { date; echo "Error - $intervals_file not detected."; } \
#>> $pipeline_log
#        exit 1
#fi
#printspace

# Run GATK CombineGVCFs OR GenomicsDBImport
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
#input_sbatch=${scripts_dir}combine_gvcfs.sbatch
input_sbatch=${scripts_dir}genomicsdbimport.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$indiv_gvcfs_dir $interval_gvcfs_dir \
$genome $interval_chunk_dir $intervals_file`
# Set dependency size for next step
dependency_size=$array_size
printspace

# Run GATK4 GenotypeGVCFs
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}genotype_gvcfs.sbatch
input_prefix=`get_prefix $input_sbatch`
jobid=`pipeliner --array $array_size \
$dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$interval_gvcfs_dir $vcfs_dir \
$genome $interval_chunk_dir $intervals_file`
# Set dependency size for next step
dependency_size=$array_size
printspace 

## Run GATK4 MergeVcfs
## Depend start upon last job step
#dependency=$jobid
#dependency_prefix=$input_prefix
#input_sbatch=${scripts_dir}merge_vcfs.sbatch
#input_prefix=`get_prefix $input_sbatch`
#jobid=`pipeliner --array $array_size \
#$dependency_prefix $dependency_size \
#$sleep_time $input_sbatch $input_prefix \
#$vcfs_dir $vcfs_dir \
#$genome $intervals_file`
## Set dependency size for next step
#dependency_size=$array_size
#printspace


# Run MultiQC on pipeline QC outputs
# Depend start upon last job step
dependency=$jobid
dependency_prefix=$input_prefix
input_sbatch=${scripts_dir}multiqc.sbatch
input_prefix=`get_prefix $input_sbatch`
if [[ $dependency ]]
then
	{ date; echo "Running $input_prefix following completion of \
$dependency_prefix step (jobid ${dependency})."; } >> $pipeline_log
	jobid=`depend $input_sbatch $input_prefix $dependency \
$qc_dir $scripts_dir`
fi
jobid=`pipeliner $dependency_prefix $dependency_size \
$sleep_time $input_sbatch $input_prefix \
$qc_dir $scripts_dir`
# Set dependency size for next step
dependency_size=1
printspace

