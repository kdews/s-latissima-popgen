#!/bin/bash
#SBATCH --time=1-0
#SBATCH -J queen_sbatch_%j.log
#SBATCH -o %x.log

## Variant calling pipeline
# Slurm-based pipeline with sequential job steps
# Controls job step submission with checkpoint files

pipeline_header="\
 ██▒   █▓▄▄▄      ██▀███  ██▓▄▄▄      ███▄    █▄▄▄█████▓    ▄████▄  ▄▄▄      ██▓    ██▓    ██▓███▄    █  ▄████ 
▓██░   █▒████▄   ▓██ ▒ ██▓██▒████▄    ██ ▀█   █▓  ██▒ ▓▒   ▒██▀ ▀█ ▒████▄   ▓██▒   ▓██▒   ▓██▒██ ▀█   █ ██▒ ▀█▒
 ▓██  █▒▒██  ▀█▄ ▓██ ░▄█ ▒██▒██  ▀█▄ ▓██  ▀█ ██▒ ▓██░ ▒░   ▒▓█    ▄▒██  ▀█▄ ▒██░   ▒██░   ▒██▓██  ▀█ ██▒██░▄▄▄░
  ▒██ █░░██▄▄▄▄██▒██▀▀█▄ ░██░██▄▄▄▄██▓██▒  ▐▌██░ ▓██▓ ░    ▒▓▓▄ ▄██░██▄▄▄▄██▒██░   ▒██░   ░██▓██▒  ▐▌██░▓█  ██▓
   ▒▀█░  ▓█   ▓██░██▓ ▒██░██░▓█   ▓██▒██░   ▓██░ ▒██▒ ░    ▒ ▓███▀ ░▓█   ▓██░██████░██████░██▒██░   ▓██░▒▓███▀▒
   ░ ▐░  ▒▒   ▓▒█░ ▒▓ ░▒▓░▓  ▒▒   ▓▒█░ ▒░   ▒ ▒  ▒ ░░      ░ ░▒ ▒  ░▒▒   ▓▒█░ ▒░▓  ░ ▒░▓  ░▓ ░ ▒░   ▒ ▒ ░▒   ▒ 
   ░ ░░   ▒   ▒▒ ░ ░▒ ░ ▒░▒ ░ ▒   ▒▒ ░ ░░   ░ ▒░   ░         ░  ▒    ▒   ▒▒ ░ ░ ▒  ░ ░ ▒  ░▒ ░ ░░   ░ ▒░ ░   ░ 
     ░░   ░   ▒    ░░   ░ ▒ ░ ░   ▒     ░   ░ ░  ░         ░         ░   ▒    ░ ░    ░ ░   ▒ ░  ░   ░ ░░ ░   ░ 
      ░       ░  ░  ░     ░       ░  ░        ░            ░ ░           ░  ░   ░  ░   ░  ░░          ░      ░ 
     ░                            ██▓███  ██▓██▓███ ▓█████ ██▓    ██▓███▄    █▓█████                           
                                 ▓██░  ██▓██▓██░  ██▓█   ▀▓██▒   ▓██▒██ ▀█   █▓█   ▀                           
                                 ▓██░ ██▓▒██▓██░ ██▓▒███  ▒██░   ▒██▓██  ▀█ ██▒███                             
                                 ▒██▄█▓▒ ░██▒██▄█▓▒ ▒▓█  ▄▒██░   ░██▓██▒  ▐▌██▒▓█  ▄                           
                                 ▒██▒ ░  ░██▒██▒ ░  ░▒████░██████░██▒██░   ▓██░▒████▒                          
                                 ▒▓▒░ ░  ░▓ ▒▓▒░ ░  ░░ ▒░ ░ ▒░▓  ░▓ ░ ▒░   ▒ ▒░░ ▒░ ░                          
                                 ░▒ ░     ▒ ░▒ ░     ░ ░  ░ ░ ▒  ░▒ ░ ░░   ░ ▒░░ ░  ░                          
                                 ░░       ▒ ░░         ░    ░ ░   ▒ ░  ░   ░ ░   ░                             
                                          ░            ░  ░   ░  ░░          ░   ░  ░                          
                                                                                                               
"

# Help message
if [[ "$1" = "-h" ]] || [[ "$1" = "--help" ]]
then
  echo "
$pipeline_header

Usage: 
  bash pipeline-s-latissima-popgen.sh [scripts_dir]
  sbatch pipeline-s-latissima-popgen.sh [scripts_dir]

Options:
  -h/--help                      print this usage message

Note: Sourced SBATCH files named with convention: <prefix>.sbatch 

Takes as input a genome and PATH to a directory containing FASTQs to align, and
outputs...

Analysis:
  indexer/
    samples_list.txt            indexes sample IDs
    individuals_file.txt        indexes individual IDs
    intervals_list.txt          indexes split interval lists
    gvcf.list                   indexes gVCF files 
    vcf.list                    indexes VCF files (in numerical order)
  wgs/                        
    *.fastq.gz                  FASTQ files renamed to shorter sample IDs 
                                (copied from source)
  trimmed_reads/
    *_val_1/2.fq.gz             reads post trimming by Trim Galore!
  bams/
    *.fasta                     reference genome (copied from source)
    *.fasta.ht2                 indexed reference genome
    *.fasta.fai                 samtools-indexed reference genome
    *.dict                      GATK4-style reference genome dictionary
    *.sorted.bam                sorted alignment files of trimmed reads to 
                                reference genome
    *.sorted.marked.bam         sorted alignment files, duplicates marked
    *.sorted.marked.merged.bam  sorted alignment files, merged by individual
  gvcfs/
    *.g.vcf.gz                  genome variant call files (gVCFs) for each
                                individual
  split_intervals/
    *-scattered.interval_list   GATK4-style lists of genomic intervals, split 
                                into as close to the desired scatter count as 
                                possible without splitting input reference 
                                contigs (e.g., scaffolds/chromosomes)
  genomicsdbimport/
    interval_*/                 GATK4-style GenomicsDB (datastore of variant
                                call data from each individual, split into 
                                groups of genomic intervals specified in 
                                *-scattered.interval_list files)
  vcfs/
    *.vcf.gz                    variant call files (VCFs) for each group of 
                                genomic intervals
  master_{genome_base}.vcf.gz   final VCF file of all samples aligned to the
                                reference genome

Quality control:
  quality_control/
    *_fastqc.zip/html           FastQC reports for all input FASTQs
    *_val_1/2_fastqc.zip/html   FASTQC reports for trimmed FASTQs
    *_trimming_report.txt       Trim Galore! trimming report for each sample
    *.hisat2.summary            HISAT2 alignment report for each sample
    *.validate.summary          validation reports of alignment (SAM/BAM) and 
                                variant (gVCF/VCF) files
    multiqc_report.html         MultiQC report summarizing QCs at each step

Logs and checkpoints:
  queen.log                     log file generated by this script
  <prefix>.log                  Slurm log files from single job steps
  <prefix>_logs/
    <prefix>_<array_#>.log      Slurm log files from batch job submissions
  checkpoints/
    <prefix>_<#>.checkpoint     checkpoint file(s) for each job step, named 
                                with the convention: 
                                <prefix>.sbatch == <prefix>_<#>.checkpoint
                                created upon job completion, where # 
                                corresponds to array index of <prefix> job step

Temporary directories:
  <prefix>_tmp                  temporary directory for a given job step

Direct any questions to Kelly DeWeese (kdeweese@mac.com)
"
  exit 0
fi

# Configure pipeline
# Main log file
pipeline_log="queen.log"
# Main pipeline config file
pipeline_config="pipeline.conf"
# User-defined input config file
user_input_config="user_input.conf"
# File created by pipeline after parsing input genome filename
genome_config="genome.conf"
# Date format for output
date_fmt="%-I:%M:%S %p (%a %d %b %Y)"
{
  echo
  echo "$pipeline_header"
  echo
  echo "Pipeline begun at $(date +"$date_fmt")"
  date +"$date_fmt"
  echo
} >> "$pipeline_log"

# Check if scripts directory specified as argument to script
if [[ -n "$1" ]]
then
  scripts_dir="$1"
else
  # Default is git name
  scripts_dir="s-latissima-popgen"
fi
# If scripts directory exists, change to realpath and append '/' to name
if [[ -d "$scripts_dir" ]]
then
  scripts_dir="$(realpath -e "$scripts_dir")"
  scripts_dir="$scripts_dir/"
  echo "Path to scripts: $scripts_dir" >> "$pipeline_log"
  # Prepend scripts path to config filenames
  pipeline_config="$(realpath -e "$scripts_dir/$pipeline_config")"
  user_input_config="$(realpath -e "$scripts_dir/$user_input_config")"
  genome_config="$(realpath -e "$scripts_dir/$genome_config")"
else
  echo "Path to scripts (current directory): $(pwd)" >> "$pipeline_log"
fi
# Attempt to source config files
{
  echo
  echo "Sourcing config files."
  echo "Pipeline config: $pipeline_config"
  echo "User input config: $user_input_config"
  echo
} >> "$pipeline_log"
if [[ -f "$pipeline_config" ]] && [[ -f "$user_input_config" ]]
then
  source "$pipeline_config"
  source "$user_input_config"
else
  echo "Error - verify config file paths." >> "$pipeline_log"
  exit 1
fi

# Create directories defined in pipeline config (if needed)
mkdir -p "$samples_dir"
mkdir -p "$indexer_dir"
mkdir -p "$qc_dir"
mkdir -p "$trimmed_dir"
mkdir -p "$bams_dir"
mkdir -p "$gvcfs_dir"
mkdir -p "$split_intervals_dir"
mkdir -p "$genomicsdbimport_dir"
mkdir -p "$vcfs_dir"
# Create "checkpoints" directory
mkdir -p checkpoints

# Report wait time to user
if (( $(( sleep_time / 60 )) < 1 ))
then
  st="$(( sleep_time / 60 )) second(s)"
elif (( $(( sleep_time / 3600 )) > 1 ))
then
  hr="$(( sleep_time / 3660 ))"
  min="$(( (sleep_time - (hr * 3600)) / 60 ))"
  st="$hr hour(s) and $min minute(s)"
else
  st="$(( sleep_time / 60 )) minute(s)"
fi
{
  echo "Wait time between checking for checkpoints set to: $st"
  echo
} >> "$pipeline_log"

# Validate and parse user-defined variables
# If genome file exists, change name to realpath
if [[ -f "$genome" ]] 
then
  genome="$(realpath -e "$genome")"
else
  echo "Genome file ($genome) not found." >> "$pipeline_log"
  exit 1
fi
# If path to raw reads exists, change name to realpath
if [[ -d "$raw_reads_dir" ]]
then
  raw_reads_dir="$(realpath -e "$raw_reads_dir")"
else
  echo "Reads directory ($raw_reads_dir) not found." >> "$pipeline_log"
  exit 1
fi

# Configure genome filenames for consistent references
# Parse input genome filename
genome_basename="$(basename "$genome")"
genome_base="${genome_basename%%.*}"
genome_basename_unzip="${genome_basename%%.gz}"
genome_local="$bams_dir/$genome_basename"
genome_local_unzip="$bams_dir/$genome_basename_unzip"
genome_dict="$bams_dir/$genome_base.dict"
genome_idx="$bams_dir/$genome_basename_unzip.fai"
ht2_idx="$bams_dir/$genome_base"
# Write the derived config for downstream steps
cat > "$genome_config" <<EOF
# Generated at "$(date +"$date_fmt")"
genome="$genome"
genome_base="$genome_base"
genome_local="$genome_local"
genome_local_unzip="$genome_local_unzip"
genome_dict="$genome_dict"
genome_idx="$genome_idx"
ht2_idx="$ht2_idx"
EOF

# Functions
# Function creates log directory for a step ($prefix) and returns directory name
make_logdir () {
  # Create log directory (if needed) from given prefix
  local logdir
  logdir="${1}_logs"
  mkdir -p "$logdir"
  echo "$logdir"
}
# Function lists checkpoint files for a step ($prefix)
ls_check () {
  local prefix
  prefix="$1"
  if [[ -z "$prefix" ]]
  then
    {
      date +"$date_fmt"
      echo "Error - no arguments given to 'ls_check'."
    } >> "$pipeline_log"
    exit 1
  fi
  # Check for array-formatted checkpoint files first
  len="$(find checkpoints -type f -name "${prefix}_[0-9]*.checkpoint" | wc -l)"
  if (( len > 0 ))
  then
    find checkpoints -type f -name "${prefix}_[0-9]*.checkpoint"
  else
    find checkpoints -type f -name "$prefix.checkpoint"
  fi
}
# Function identifies checkpoint files for a step ($prefix) and
# returns a string of array indices (e.g., 1,2,4,) for missing checkpoint files
miss_check () {
  local prefix
  local array_size
  prefix="$1"
  array_size="$2"
  if [[ $# -ne 2 ]]
  then
    {
      date +"$date_fmt"
      echo "Error - 'miss_check' expected 2 arguments but received $#."
      echo "Arguments: $*"
    } >> "$pipeline_log"
    exit 1
  fi
  if [[ -n "$(ls_check "$prefix")" ]]
  then
    for i in $(seq "$array_size")
    do
      if [[ ! -f "checkpoints/${prefix}_$i.checkpoint" ]]
      then
        printf "%s," "$i"
      fi
    done
  else
    echo "Error - no checkpoints found for step: $prefix" >> "$pipeline_log"
    exit 1
  fi
}
# Function runs job step (unless previous run succeeded)
# For array jobs, will submit only array indices for missing checkpoints
run_step () {
  local array_size
  local prefix
  local step_args
  local sbatch_file
  local logdir
  local logfile
  local num_checks
  local array_indices
  local array_flag
  local cmd

  # Arguments to function
  array_size="$1" # array size for job (integer)
  prefix="$2" # prefix of sbatch file for job (string)
  # Parse repeat calls to same sbatch file (prefix=<prefix>-#)
  prefix_base="${prefix%-[0-9]*}"

  # Log function call
  echo "run_step $*" >> "$pipeline_log"
  
  # Name sbatch file from prefix
  sbatch_file="${scripts_dir}$prefix_base.sbatch"

  # Name log file(s)
  if (( array_size > 1 ))
  then
    # For array jobs, write logs to directory <prefix>_logs
    logdir="$(make_logdir "$prefix")"
    logfile="$logdir/%x_%a.log"
  else
    # For single jobs, write log to working directory
    logfile="%x.log"
  fi

  # Check for any existing checkpoints for prefix
  if [[ -n "$(ls_check "$prefix")" ]]
  then
    num_checks="$(ls_check "$prefix" | wc -l)" # count of checkpoint files
    echo "$num_checks checkpoint(s) detected for $prefix" >> "$pipeline_log"
    # Skip job step if all checkpoints exist
    if [[ "$num_checks" -eq "$array_size" ]]
    then
      echo "$prefix step already run. Skipping." >> "$pipeline_log"
      return 0
    # If some checkpoints missing for array jobs, submit only those array indices
    elif (( array_size > 1 ))
    then
      # Use missing checkpoints to set array indices for submission
      array_indices="$(miss_check "$prefix" "$array_size")"
      array_flag="--array=$array_indices"
      {
        echo "Missing checkpoints for $prefix step. Restarting."
        echo "Submitting job array indices: $array_indices"
      } >> "$pipeline_log"
    # Catch unexpected checkpoint errors
    else
      echo "Error - inspect checkpoints for step: $prefix" >> "$pipeline_log"
      return 1
    fi
  else
    # Set sbatch --array flag for array jobs
    (( array_size > 1 )) && array_flag="--array=1-$array_size"
    echo "Running $prefix step." >> "$pipeline_log"
  fi
  # Pass arguments to specific step script
  step_args=(
    "$prefix" # $1 to sbatch file
    "$genome_config" # $2 to sbatch file
    "${@:3}" # captures all remaining arguments to function
  )
  # Job submission command
  if [[ -n "$array_flag" ]]
  then
    cmd=(
      sbatch
      --parsable
      -p "$partition"
      -J "$prefix"
      -o "$logfile"
      "$array_flag"
      "$sbatch_file"
      "${step_args[@]}"
    )
  else
    cmd=(
      sbatch
      --parsable
      -p "$partition"
      -J "$prefix"
      -o "$logfile"
      "$sbatch_file"
      "${step_args[@]}"
    )
  fi
  # Log job submission
  echo "${cmd[*]}" >> "$pipeline_log"
  jobid="$("${cmd[@]}")"
  echo "Submitted batch job $jobid" >> "$pipeline_log"
}

# Array containing arguments to each step of pipeline
PIPELINE_STEPS=(
#   [#_step]="<prefix>|[--array]|<input_dir>|<output_dir>|[index_file]|[extra_args]"
  "prep_ref|$bams_dir|$bams_dir"
  "rename|$raw_reads_dir|$samples_dir|$samples_list|$scripts_dir"
  "fastqc|--array|$samples_dir|$qc_dir|$samples_list"
  "trim_galore|--array|$samples_dir|$trimmed_dir|$samples_list|$qc_dir"
  "hisat2_build|$bams_dir|$bams_dir"
  "hisat2|--array|$trimmed_dir|$bams_dir|$samples_list|$qc_dir|$indiv_list"
  "validate_sams|--array|$bams_dir|$qc_dir|$samples_list|.sorted.bam"
  "collect_metrics|--array|$bams_dir|$qc_dir|$samples_list"
  "mark_dupes|--array|$bams_dir|$bams_dir|$samples_list|$qc_dir"
  "validate_sams|--array|$bams_dir|$qc_dir|$samples_list|.sorted.marked.bam"
  "collapse_bams|--array|$bams_dir|$bams_dir|$indiv_list"
  "validate_sams|--array|$bams_dir|$qc_dir|$indiv_list|.sorted.marked.merged.bam"
  "index_bams|--array|$bams_dir|$bams_dir|$indiv_list"
  "haplotype_caller|--array|$bams_dir|$gvcfs_dir|$indiv_list"
  "validate_variants|--array|$gvcfs_dir|$qc_dir|$gvcf_list"
  "split_intervals|$split_intervals_dir|$split_intervals_dir|$intervals_list|$scatter"
  "genomicsdbimport|--array|$gvcfs_dir|$genomicsdbimport_dir|$intervals_list|$gvcf_list"
  "genotype_gvcfs|--array|$gvcfs_dir|$vcfs_dir|$indiv_list"
  "sort_vcf|--array|$vcfs_dir|$vcfs_dir|$vcf_list"
  "validate_variants|--array|$vcfs_dir|$qc_dir|$vcf_list"
  "merge_vcfs|$vcfs_dir|$vcfs_dir|$vcf_list"
  "multiqc|$qc_dir|$multiqc_dir|$scripts_dir"
)

# Run pipeline
declare -A PREFIX_COUNT  # track how many times each prefix appears for naming
for step in "${!PIPELINE_STEPS[@]}"
do
  # Wait to submit next step until previous completes
  # (Avoids QOSMax errors from Slurm sometimes triggered by dependent jobs)
  if [[ -n "$dep_prefix" ]] && [[ -n "$dep_size" ]]
  then
    # Compare dependency array size to count of checkpoint files
    # Waits until # of checkpoint files = array size
    until [[ "$(ls_check "$dep_prefix" | wc -l)" -eq "$dep_size" ]]
    do
      {
        date +"$date_fmt"
        echo "Waiting $st for completion of $dep_prefix step."
      } >> "$pipeline_log"
      sleep "$sleep_time"
    done
    # Step-specific tasks
    # After hisat2 step: sort individual ID list
    if [[ "$dep_prefix" = "hisat2" ]] && [[ -f "$indiv_list" ]]
    then
      echo "Sorting $indiv_list for unique invidual IDs." >> "$pipeline_log"
      sort -u "$indiv_list" > "${indiv_list}_sorted"
      mv "${indiv_list}_sorted" "$indiv_list"
    elif [[ "$dep_prefix" = "hisat2" ]] && [[ ! -f "$indiv_list" ]]
    then
      echo "Error - invidual ID list ($indiv_list) not found." >> "$pipeline_log"
      exit 1
    fi
    # After haplotype_caller step: create gVCF list
    if [[ "$dep_prefix" = "haplotype_caller" ]]
    then
      echo "Creating list of gVCFs: $gvcf_list" >> "$pipeline_log"
      find "$gvcfs_dir" -type f -name "*$genome_base.g.vcf.gz" > "$gvcf_list"
      if [[ "$(wc -l < "$gvcf_list")" -ne "$dep_size" ]]
      then
        echo "Error - incorrect # of files in $gvcf_list" >> "$pipeline_log"
        exit 1
      fi
    fi
    # After genotype_gvcfs step: create VCF list
    if [[ "$dep_prefix" = "genotype_gvcfs" ]]
    then
      echo "Creating list of VCF files: $vcf_list" >> "$pipeline_log"
      find "$vcfs_dir" -type f -name "*$genome_base.vcf.gz" > "$vcf_list"
      if [[ "$(wc -l < "$vcf_list")" -ne "$dep_size" ]]
      then
        echo "Error - incorrect # of files in $vcf_list"  >> "$pipeline_log"
        exit 1
      fi
    fi
    # After sort_vcf step: overwrite VCF list with sorted VCF filenames
    if [[ "$dep_prefix" = "sort_vcf" ]]
    then
      echo "Overwritting VCF list: $vcf_list" >> "$pipeline_log"
      find "$vcfs_dir" -type f -name "*$genome_base.sorted.vcf.gz" > "$vcf_list"
      if [[ "$(wc -l < "$vcf_list")" -ne "$dep_size" ]]
      then
        echo "Error - incorrect # of files in $vcf_list" >> "$pipeline_log"
        exit 1
      fi
    fi
  fi

  # Convert stored string into array from separator
  IFS="|" read -r -a args <<< "${PIPELINE_STEPS[$step]}"
  # Parse step name
  prefix="${args[0]}"

  # Handles multiple steps using same sbatch file
  count="${PREFIX_COUNT[$prefix]:-0}" # if no stored value, set count to zero
  ((count++)) # increment count
  PREFIX_COUNT[$prefix]="$count" # store count for $prefix array entry
  ((count > 1)) && prefix="${prefix}-$count" # append "-n" to repeat $prefix

  # Log step
  {
    date +"$date_fmt"
    echo "Step #$((step + 1)): $prefix"
  } >> "$pipeline_log"

  # Parse batch array jobs
  if [[ "${args[1]}" = "--array" ]]
  then
    # Set array size based on index file length
    index_file="${args[4]}"
    if [[ -f "$index_file" ]]
    then
      array_size="$(wc -l < "$index_file")"
      args=( "$prefix" "${args[@]:2}" )
    else
      echo "Error - index file ($index_file) not found."  >> "$pipeline_log"
      exit 1
    fi
  else
    # Set array size
    array_size=1
  fi
  echo "Array size set to: $array_size" >> "$pipeline_log"

  # Run pipeline step
  run_step "$array_size" "${args[@]}"

  # Update dependency info for next step
  dep_prefix="$prefix"
  dep_size="$array_size"
  
  echo >> "$pipeline_log"
done

# Pipeline end
echo "Pipeline completed at $(date +"$date_fmt")"
