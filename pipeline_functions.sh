#!/bin/bash

# Functions for pipeline execution
# Default logging settings (no logging by default)
PIPELINE_LOGGING_ENABLED="${PIPELINE_LOGGING_ENABLED:-false}"

# Lightweight no-op logger
_log() {
  local date_fmt="${date_fmt:-"%-I:%M:%S %p (%a %d %b %Y)"}"
  local pipeline_log="${pipeline_log:-/dev/null}"
  if [[ "$PIPELINE_LOGGING_ENABLED" == true ]]
  then
    if [[ -z "$*" ]]
    then
      echo >> "$pipeline_log"
    else
      {
        date +"$date_fmt"
        printf '%s\n' "$*"
      } >> "$pipeline_log"
    fi
  fi
}

# Function lists checkpoint files for a step ($prefix)
ls_check () {
  local prefix="$1"
  if [[ -z "$prefix" ]]
  then
    _log "Error - no arguments passed to 'ls_check'."
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
  local prefix="$1"
  local array_size="$2"
  if [[ $# -ne 2 ]]
  then
    _log "Error - miss_check expected 2 arguments but got $#: $*"
    exit 1
  fi
  if [[ -n "$(ls_check "$prefix")" ]]
  then
    for i in $(seq "$array_size")
    do
      if [[ ! -f "checkpoints/${prefix}_$i.checkpoint" ]]
      then
        # Handle trailing comma
        if [[ "$i" -eq "$array_size" ]]
        then
          printf "%s" "$i"
        else
          printf "%s," "$i"
        fi
      fi
    done
  else
    _log "Error - no checkpoints found for job step: $prefix"
    exit 1
  fi

}
# Function runs job step (unless previous run succeeded)
# For array jobs, will submit only array indices for missing checkpoints
run_step () {
  # Log function call
  _log "run_step $*"

  # Arguments to function
  local array_size="$1" # array size for job (integer)
  local genome_config="$2" # genome config file (string)
  local prefix="$3" # prefix of sbatch file for job (string)

  # Maximum number of jobs to launch concurrently (takes global var max_run)
  local max_run="${max_run:-50}" # default = 50
  # Name of scripts directory (takes global var scripts_dir)
  local scripts_dir="${scripts_dir:-s-latissima-popgen/}" # default = s-latissima-popgen/
  # Name of Slurm partition to use (takes global)
  local partition="${partition:-main}" # default: main

  # Parse repeat calls to same sbatch file (prefix=<prefix>-#)
  local prefix_base="${prefix%-[0-9]*}"
  # Name sbatch file from prefix BASE (no increments)
  local sbatch_file="${scripts_dir}$prefix_base.sbatch"
  # Name log file(s)
  if (( array_size > 1 ))
  then
    # For array jobs, write logs to directory <prefix>_logs
    # Shoutout GOATED Slurm release 23.02
    local logfile="%x_logs/%x_%a.log"
  else
    # For single jobs, write log to working directory
    local logfile="%x.log"
  fi

  # Check for any existing checkpoints for prefix
  if [[ -n "$(ls_check "$prefix")" ]]
  then
    local num_checks
    num_checks="$(ls_check "$prefix" | wc -l)" # count of checkpoint files
    _log "$num_checks checkpoint(s) detected for $prefix"
    # Skip job step if all checkpoints exist
    if [[ "$num_checks" -eq "$array_size" ]]
    then
      _log "$prefix step already run. Skipping."
      return 0
    # If some checkpoints missing for array jobs, submit only those array indices
    elif (( array_size > 1 ))
    then
      # Use missing checkpoints to set array indices for submission
      local array_indices
      array_indices="$(miss_check "$prefix" "$array_size")"
      local array_flag="--array=$array_indices%$max_run"
      _log "Missing checkpoints for $prefix step. Restarting."
      _log "Submitting job array indices: $array_indices"
    # Catch unexpected checkpoint errors
    else
      _log "Error - inspect checkpoints for step: $prefix"
      return 1
    fi
  else
    # Set sbatch --array flag for array jobs
    (( array_size > 1 )) && local array_flag="--array=1-$array_size%$max_run"
    _log "Running $prefix step."
  fi
  # Pass arguments to specific step script
  local step_args=(
    "$prefix" # $1 to sbatch file
    "$genome_config" # $2 to sbatch file
    "${@:4}" # captures all remaining arguments to function
  )
  # Job submission command
  if [[ -n "$array_flag" ]]
  then
    local cmd=(
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
    local cmd=(
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
  _log "${cmd[*]}"
  local jobid
  jobid="$("${cmd[@]}")"
  _log "Submitted batch job $jobid"
}