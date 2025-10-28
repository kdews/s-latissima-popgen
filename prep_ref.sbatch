#!/bin/bash
#SBATCH --mem=500mb
#SBATCH --time=02:00:00

prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
genome="$4" # genome FASTA

# Parse genome filename
genome_basename="$(basename "$genome")"
genome_base="${genome_basename%%.*}"
genome_basename_unzip="${genome_basename%%.gz}"
genome_dict="$outdir/$genome_base.dict"

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version

# Build FASTA dictionary
cmd=(
    gatk CreateSequenceDictionary
    -R "$indir/$genome_basename_unzip"
    -O "$outdir/$genome_dict"
)
echo "${cmd[*]}"
"${cmd[@]}"
unset cmd

# Load samtools
module purge
conda activate samtools
samtools --version

# Build samtools FASTA index
cmd=(
    samtools faidx
    "$indir/$genome_basename_unzip"
)
echo "${cmd[*]}"
"${cmd[@]}"

# Checkpoint
files_exist_gatk () {
    if compgen -G "${indir}/${1}*.dict" > /dev/null
    then
        echo "true"
    else
        echo "false"
    fi
}

files_exist_sam () {
    if compgen -G "${indir}/${1}*.fai" > /dev/null
    then
        echo "true"
    else
        echo "false"
    fi
}
if [[ $? -eq 0 ]]
then
    cd ..
    if [[ `files_exist_gatk ${genome_base}` == "true" ]] && \
[[ `files_exist_sam ${genome_base}` == "true" ]]
    then
        if [[ ! -d checkpoints ]]
        then
            mkdir checkpoints
        fi
        echo "Success"
        touch checkpoints/${prefix}.checkpoint
        exit 0
    else
        echo "Error - ${genome_base} dictionary & \
index files not detected in '${indir}' directory. Checkpoint not created."
    fi
else
    echo "Error - non-zero exit code returned by GATK4 or samtools."
    exit 1
fi

