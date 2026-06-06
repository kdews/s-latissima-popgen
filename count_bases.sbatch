#!/bin/bash
#SBATCH -J genomicsdbimport
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=01:00:00
#SBATCH --mem=50g
#SBATCH --cpus-per-task=8

# Script variables
# Extract job name from script
if [[ -z "${SLURM_JOB_NAME}" ]]
then
  job_name="$(basename "$0")"
  job_name="${job_name%%.*}"
else
  job_name="$SLURM_JOB_NAME"
fi
rscript="$job_name.R" # R script to run
scripts_dir="s-latissma-popgen" # scripts directory
[[ -d "$scripts_dir" ]] && rscript="${scripts_dir}${rscript}"
# Output
out_table="raw_base_counts.txt"

# Help message
show_help () {
  echo "\
Parses data in FASTQC output zipped directories to get raw count of bases for
each FASTQ.

Usage: sbatch $job_name.sbatch <fastqc_res_dir>
  <fastqc_res_dir>     directory containing FASTQC *.zip results

Output:
  .
  ├── $out_table       # table of raw base counts from each FASTQC result
  └── [scripts_dir]           # optional: directory containing R script
      └── base_counts.png     # distribution of raw base counts

Requires:
  - R v4.6.0 (https://cran.r-project.org/)
  - tidyverse (https://tidyverse.org/)
  - ggpubr (https://rpkgs.datanovia.com/ggpubr/)"
}
if [[ $1 == "-h" || $1 == "--help" ]]
then
  show_help
  exit 0
elif [[ "$#" -ne 1 ]]
then
  echo "Error: 1 positional argument required."
  echo
  show_help
  exit 1
fi

# -e  exit on error
# -o pipefail  catch errors in pipes
set -eo pipefail

# Print date and time
date
echo

# Input
# fastqc_res_dir="quality_control"
fastqc_res_dir="$1"
if [[ -d "$fastqc_res_dir" ]]
then
  echo "Using directory: $fastqc_res_dir"
else
  echo "Error: input directory ($fastqc_res_dir) not found."
  exit 1
fi
echo

# Extract raw base counts from each FASTQC .zip directory
for f in "$fastqc_res_dir"/*R[12]_fastqc.zip
do
  # unzip -p "$f" "*/fastqc_data.txt" | grep "Total Bases" | cut -f2
  {
    echo -n "$(basename "$f"): "
    unzip -p "$f" "*/fastqc_data.txt" | grep "Total Bases" | awk '{print $NF}'
  } >> "$out_table"
done

# Load R module
module purge
module load r/4.6.0
Rscript --version || exit 1
echo

# Run Rscript
set -x
Rscript "$rscript" "$out_table" "$scripts_dir"
set +x

# Done
echo
echo "Finished at: $(date)"
