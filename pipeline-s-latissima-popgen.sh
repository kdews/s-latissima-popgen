#!/bin/bash
#SBATCH --time=1-0
#SBATCH -J queen
#SBATCH -o queen_sbatch_%j.log

# -e  exit on error
# -o pipefail  catch errors in pipes
set -eo pipefail

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
show_help () {
  echo "
$pipeline_header

Usage: 
  bash pipeline-s-latissima-popgen.sh [scripts_dir]
  sbatch pipeline-s-latissima-popgen.sh [scripts_dir]

Options:
  -h/--help        print this usage message

Notes:
  - Slurm scripts and logs are named with the convention:
    - <prefix>.sbatch                                    # job submission script
    - <prefix>.log                                          # non-array job logs
    - <prefix>_logs/<prefix>_#.log                              # array job logs
  - Final genotyped VCFs are named:
    - <vcf_base>.vcf.gz                  # vcf_base = master_<year>_<ref>, where
                                         # ref = reference FASTA filename base

Output:
  .
  ├── bam_stats_logs                  # Slurm log files for array job submission
  ├── bams
  |   ├── <ref>.fasta                                # reference genome (copied)
  |   ├── <ref>.fasta.ht2                             # indexed reference genome
  |   ├── <ref>.fasta.fai                    # samtools-indexed reference genome
  |   ├── <ref>.dict                   # GATK4-style reference genome dictionary
  |   ├── <sample_ID>_<ref>.sorted.bam               # initial sorted alignments
  |   └── <indiv_ID>_<ref>.sorted.marked.bam # final duplicate-marked alignments
  ├── bcftools_concat.log                                       # Slurm log file
  ├── bcftools_stats.log                                        # Slurm log file
  ├── checkpoints
  |   ├── <prefix>.checkpoint             # checkpoint for non-array job success
  |   └── <prefix>_<#>.checkpoint         # checkpoint for array (#) job success
  ├── collect_metrics_logs            # Slurm log files for array job submission
  ├── fastp_logs                      # Slurm log files for array job submission
  ├── fastqc_logs                     # Slurm log files for array job submission
  ├── gather_vcfs.log                                           # Slurm log file
  ├── genomicsdbimport
  |   └── interval_#                  # GATK4-style GenomicsDB for each interval
  ├── genomicsdbimport_logs           # Slurm log files for array job submission
  ├── genotype_gvcfs_logs             # Slurm log files for array job submission
  ├── gvcfs
  |   └── <indiv_ID>.g.vcf.gz         # per-indiviudal genome variant call files
  ├── haplotype_caller_logs           # Slurm log files for array job submission
  ├── hisat2_build.log                                          # Slurm log file
  ├── hisat2_logs                     # Slurm log files for array job submission
  ├── indexer                                                # indexes for input
  |   ├── samples_list.txt                                     # sample ID index
  |   ├── individuals_file.txt                             # individual ID index
  |   ├── intervals_list.txt                         # split interval list index
  |   ├── gvcf.sample_map                # GATK4-style sample map for gVCF files 
  |   └── vcf.list                     # index of VCF files (in numerical order)
  ├── mark_dupes_logs                 # Slurm log files for array job submission
  ├── multiqc.log                                               # Slurm log file
  ├── multiqc_data_<date>
  |   ├── multiqc_report_<date>_data                       # MultiQC report data
  |   └── multiqc_report_<date>.html                    # MultiQC report summary
  ├── prep_ref.log                                              # Slurm log file
  ├── quality_control                               # QC reports after each step
  |   ├── <sample_ID>_R#_fastqc.html                   # raw read FastQC reports
  |   ├── <sample_ID>_R#_fastqc.zip                       # raw read FastQC data
  |   ├── <sample_ID>_fastp.html                      # fastp trimming QC report
  |   ├── <sample_ID>_fastp.json                        # fastp trimming QC data
  |   ├── <sample_ID>_R#_fastp_fastqc.html         # trimmed read FastQC reports
  |   ├── <sample_ID>_R#_fastp_fastqc.zip             # trimmed read FastQC data
  |   ├── <sample_ID>_<ref>.hisat2.summary          # HISAT2 alignment QC report
  |   ├── <sample_ID>_<ref>.sorted.bam.validate.summary        # ValidateSamFile
  |   ├── <indiv_ID>_<ref>.marked_dup_metrics.txt    # MarkDuplicates QC metrics
  |   ├── <indiv_ID>_<ref>.sorted.marked.bam.validate.summary  # ValidateSamFile
  |   ├── <indiv_ID>_<ref>.alignment_summary_metrics.txt # CollectAlignmentSummaryMetrics
  |   ├── <indiv_ID>_<ref>.read_length_histogram.pdf  # CollectAlignmentSummaryMetrics
  |   ├── <indiv_ID>_<ref>.collect_wgs_metrics.txt           # CollectWgsMetrics
  |   ├── <indiv_ID>_<ref>.insert_size_histogram.pdf  # CollectInsertSizeMetrics
  |   ├── <indiv_ID>_<ref>.insert_size_metrics.txt    # CollectInsertSizeMetrics
  |   ├── <indiv_ID>_<ref>.quality_yield_metrics.txt # CollectQualityYieldMetrics
  |   ├── <indiv_ID>_<ref>.stats    # samtools stats QC of final alignment files
  |   ├── <vcf_base>.bcftools.stats      # bcftools stats QC report of final VCF
  |   └── <vcf_base>.variant_eval.txt       # VariantEval QC report of final VCF
  ├── queen.log                                                   # pipeline log
  ├── rename.log                                                # Slurm log file
  ├── split_intervals
  |   └── ####-scattered.interval_list  # GATK4-style lists of genomic intervals
  ├── split_intervals.log                                       # Slurm log file
  ├── trim_galore_logs                # Slurm log files for array job submission
  ├── trimmed_reads
  |   └── <sample_ID>_R#_fastp.fastq.gz                 # reads trimmed by fastp
  ├── validate_sams-2_logs            # Slurm log files for array job submission
  ├── validate_sams_logs              # Slurm log files for array job submission
  ├── validate_variants-2_logs        # Slurm log files for array job submission
  ├── validate_variants-3.log         # Slurm log files for array job submission
  ├── validate_variants_logs          # Slurm log files for array job submission
  ├── variant_eval.log                                          # Slurm log file
  ├── vcfs
  |   ├── interval_#_<ref>.vcf.gz                        # VCFs at each interval
  |   └── <vcf_base>.vcf.gz          # final VCF combined over genomic intervals
  └── wgs
      └── <sample_ID>_R#.fastq.gz            # renamed paired-end reads (copied)

Direct any questions to Kelly DeWeese (kdeweese@mac.com)
"
}
if [[ "$1" = "-h" || "$1" = "--help" ]]
then
  show_help
  exit 0
fi

# Configure pipeline
# Main log file
pipeline_log="queen.log"
# Main pipeline config file
pipeline_config="pipeline.conf"
# User-defined input config file
user_input_config="user_input.conf"
# Pipeline functions
pipeline_func="pipeline_functions.sh"
# Configure logging for functions
PIPELINE_LOGGING_ENABLED=true
# File created by pipeline after parsing input genome filename
genome_config="genome.conf"
year="$(date +%Y)" # current year
date_fmt="%-I:%M:%S %p (%a %d %b %Y)" # date format
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
  scripts_dir="$(realpath -se --relative-to=. "$scripts_dir")"
  scripts_dir="$scripts_dir/"
  echo "Path to scripts: $scripts_dir" >> "$pipeline_log"
  # Prepend scripts path to config filenames
  pipeline_config="$(realpath -se --relative-to=. "$scripts_dir/$pipeline_config")"
  user_input_config="$(realpath -se --relative-to=. "$scripts_dir/$user_input_config")"
  pipeline_func="$(realpath -se --relative-to=. "$scripts_dir/$pipeline_func")"
  genome_config="$(realpath -se --relative-to=. "$scripts_dir/$genome_config")"
else
  echo "Path to scripts (current directory): $(pwd)" >> "$pipeline_log"
fi
# Attempt to source config files
{
  echo
  echo "Sourcing config files."
  echo "Pipeline config: $pipeline_config"
  echo "User input config: $user_input_config"
  echo "Pipeline functions: $pipeline_func"
  echo
} >> "$pipeline_log"
if [[ -f "$pipeline_config" ]] \
  && [[ -f "$user_input_config" ]] \
  && [[ -f "$pipeline_func" ]]
then
  source "$pipeline_config"
  source "$user_input_config"
  source "$pipeline_func"
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
_log "Wait time between checking for checkpoints set to: $st"
_log "Maximum jobs to launch simultaneously set to: $max_run"
_log

# Validate and parse user-defined variables
# If genome file exists, change name to realpath
if [[ -f "$genome" ]] 
then
  genome="$(realpath -e "$genome")"
else
  _log "Genome file ($genome) not found."
  exit 1
fi
# If path to raw reads exists, change name to realpath
if [[ -d "$raw_reads_dir" ]]
then
  raw_reads_dir="$(realpath -e "$raw_reads_dir")"
else
  _log "Reads directory ($raw_reads_dir) not found."
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

# Array containing arguments to each step of pipeline
PIPELINE_STEPS=(
#   [#_step]="<prefix>|[--array]|<input_dir>|<output_dir>|[index_file]|[extra_args]"
  "prep_ref|$bams_dir|$bams_dir"
  "rename|$raw_reads_dir|$samples_dir|$samples_list|$scripts_dir"
  "fastqc|--array|$samples_dir|$qc_dir|$samples_list"
  "fastp|--array|$samples_dir|$trimmed_dir|$samples_list|$qc_dir"
  "hisat2_build|$bams_dir|$bams_dir"
  "hisat2|--array|$trimmed_dir|$bams_dir|$samples_list|$qc_dir|$indiv_list"
  "validate_sams|--array|$bams_dir|$qc_dir|$samples_list|.sorted.bam"
  "mark_dupes|--array|$bams_dir|$bams_dir|$indiv_list|$qc_dir"
  "validate_sams|--array|$bams_dir|$qc_dir|$indiv_list|.sorted.marked.bam"
  "collect_metrics|--array|$bams_dir|$qc_dir|$indiv_list"
  "haplotype_caller|--array|$bams_dir|$gvcfs_dir|$indiv_list"
  "validate_variants|--array|$gvcfs_dir|$qc_dir|$indiv_list|.g.vcf.gz"
  "split_intervals|$split_intervals_dir|$split_intervals_dir|$intervals_list|$scatter"
  "genomicsdbimport|--array|$gvcfs_dir|$genomicsdbimport_dir|$intervals_list|$gvcf_map"
  "genotype_gvcfs|--array|$genomicsdbimport_dir|$vcfs_dir|$intervals_list"
  "validate_variants|--array|$vcfs_dir|$qc_dir|$intervals_list|.vcf.gz"
  "bcftools_concat|$vcfs_dir|$vcfs_dir|$vcf_list"
  "validate_variants|$vcfs_dir|$qc_dir|master_$year|.vcf.gz"
  "variant_eval|$vcfs_dir|$qc_dir"
  "bcftools_stats|$vcfs_dir|$qc_dir"
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
      _log "Waiting $st for completion of $dep_prefix step."
      sleep "$sleep_time"
    done
    # Step-specific tasks
    # After hisat2 step: sort individual ID list
    if [[ "$dep_prefix" = "hisat2" ]] && [[ -f "$indiv_list" ]]
    then
      _log "Sorting $indiv_list for unique invidual IDs."
      # Sort and keep only non-empty lines
      sort -u "$indiv_list" | grep -v -x '[[:blank:]]*' > "${indiv_list}_sorted"
      mv "${indiv_list}_sorted" "$indiv_list"
    elif [[ "$dep_prefix" = "hisat2" ]] && [[ ! -f "$indiv_list" ]]
    then
      _log "Error - invidual ID list ($indiv_list) not found."
      exit 1
    fi
    # After haplotype_caller step: create gVCF list
    if [[ "$dep_prefix" = "haplotype_caller" ]]
    then
      _log "Creating sample map file of gVCFs: $gvcf_map"
      mapfile -t indivs < "$indiv_list"
      for id in "${indivs[@]}"
      do
        gvcf="$gvcfs_dir/${id}_$genome_base.g.vcf.gz"
        if [[ -f "$gvcf" ]]
        then
          echo -e "$id\t$gvcf"
        else
          _log "Error - gVCF ($gvcf) not found for $id"
          exit 1
        fi
      done > "$gvcf_map"
      if [[ "$(wc -l < "$gvcf_map")" -ne "$dep_size" ]]
      then
        _log "Error - incorrect # of gVCFs in $gvcf_map"
        exit 1
      fi
    fi
    # After genotype_gvcfs step: create VCF filename list
    if [[ "$dep_prefix" = "genotype_gvcfs" ]]
    then
      _log "Creating VCF list: $vcf_list"
      mapfile -t ints < "$intervals_list"
      for i in "${!ints[@]}"
      do
        n="$(( i + 1 ))"
        vcf="$vcfs_dir/interval_${n}_$genome_base.vcf.gz"
        if [[ -f "$vcf" ]]
        then
          echo "$vcf"
        else
          _log "Error - VCF ($vcf) not found."
          exit 1
        fi
      done > "$vcf_list"
      if [[ "$(wc -l < "$vcf_list")" -ne "$dep_size" ]]
      then
        _log "Error - incorrect # of files in $vcf_list"
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
  _log "Step #$((step + 1)): $prefix"

  # Parse batch array jobs
  if [[ "${args[1]}" = "--array" ]]
  then
    # Set array size based on index file length
    index_file="${args[4]}"
    if [[ -f "$index_file" ]]
    then
      array_size="$(wc -l < "$index_file")"
      # Remove array flag and update $prefix with count
      args=( "$prefix" "${args[@]:2}" )
    else
      _log "Error - index file ($index_file) not found."
      exit 1
    fi
  else
    # Set array size
    array_size=1
    # Update $prefix with count
    args=( "$prefix" "${args[@]:1}" )
  fi
  _log "Array size set to: $array_size"

  # Run pipeline step
  run_step "$array_size" "$genome_config" "${args[@]}"

  # Update dependency info for next step
  dep_prefix="$prefix"
  dep_size="$array_size"
  
  _log
done

# Pipeline end
_log "Pipeline completed."
