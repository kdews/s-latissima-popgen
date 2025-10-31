#!/bin/bash
#SBATCH -J test_qos_limits
#SBATCH -o %x_logs/%x_%a.log
#SBATCH --time=1

echo "Parition: $SLURM_JOB_PARTITION"
echo "Array ID: $SLURM_ARRAY_TASK_ID"