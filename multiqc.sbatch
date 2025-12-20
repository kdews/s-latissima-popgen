#!/bin/bash
#SBATCH -J multiqc
#SBATCH -o %x.log
#SBATCH --time=01:00:00
#SBATCH --mem=15g

# Log Slurm job details
if [[ -n "$SLURM_ARRAY_TASK_ID" ]]
then
  echo "Slurm array job ID: ${SLURM_ARRAY_JOB_ID}_$SLURM_ARRAY_TASK_ID"
fi
echo "Partition: $SLURM_JOB_PARTITION"

# Print date and time
date_fmt="%-I:%M:%S %p (%a %d %b %Y)" # date format
date +"$date_fmt"
echo

# Input
prefix="$1" # job name
genome_config="$2" # genome config file
indir="$3" # input directory
outdir="$4" # output directory (default parsed data directory name)
scripts_dir="$5" # optional: directory containing scripts (MUST end in '/')

# MultiQC output file
date_str="$(date +"%m_%d_%y")" # filename date format
out_report="multiqc_report_$date_str.html"
# MultiQC config file
multiqc_config="multiqc_config.yaml"
# If $scripts_dir exists, prepend path to config
if [[ -d "$scripts_dir" ]]
then
  multiqc_config="${scripts_dir}${multiqc_config}"
fi

# Verify input directory exists
if [[ -d "$indir" ]]
then
  echo "Running MultiQC on: $indir"
else
  echo "Error - input directory to MultiQC ($indir), not found."
fi

# Load conda
cond=~/.conda_for_sbatch.sh
if [[ -f "$cond" ]]
then
  source "$cond"
else
  echo "Error on source of $cond"
  exit 1
fi

# Load MultiQC
conda activate multiqc
multiqc --version || exit 1

# Run MultiQC
cmd=(
  multiqc
  -c "$multiqc_config"
  -n "$out_report"
  # --replace-names multiqc_rename_samples.tsv
  "$indir"
)
echo "${cmd[*]}"
"${cmd[@]}" && check="pass"

# Mark time at completion
echo; date +"$date_fmt"; echo

# Checkpoints
mkdir -p checkpoints
if [[ "$check" == "pass" ]] && [[ -f "$out_report" ]] && [[ -d "$outdir" ]]
then
  echo "Creating checkpoint."
  touch "checkpoints/$prefix.checkpoint"
  exit 0
else
  echo "Error - MultiQC report not created."
  echo "Checkpoint not created."
  exit 1
fi

