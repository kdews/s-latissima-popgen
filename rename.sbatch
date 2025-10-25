#!/bin/bash
#SBATCH --mem=20gb
#SBATCH --time=03:30:00
#SBATCH --cpus-per-task=20

# Print date and time
date
echo

# Input
prefix="$1" # sbatch filename without file extensions
indir="$2" # input directory
outdir="$3" # output directory
logdir="${prefix}_logs" # log directory
samples_file="$4" # file to save parsed sample IDs
# Optional, to specify directory containing scripts
# MUST end in '/'
scripts_dir="$5"
# File contianing original FASTQ paths
og_file="$logdir/original_filenames.txt"
rsync_list="$logdir/rsync_list.txt"

# List original FASTQ paths
cmd=(
   find
   "$indir"
   -mindepth 2
   -maxdepth 2
   -type f
   -name "*.fastq.gz"
   -exec realpath -e {} \;
)
echo "${cmd[*]} > $og_file"
"${cmd[@]}" > "$og_file"
unset cmd

# Create new output directory (if needed)
echo "Output directory: ${outdir}"
mkdir -p "$outdir"

# Run rename Python script
cmd=(
    python
    "${scripts_dir}rename_MO_KD.py"
    "$og_file"
    "$outdir"
    "$rsync_list"
)
echo "${cmd[*]}"
"${cmd[@]}"
unset cmd

module purge
module load ver/2506 gcc/14.3.0 parallel
parallel --version
parallel -j "$SLURM_CPUS_PER_TASK" < "$rsync_list"

# Make $samples_file from FASTQs in $outdir
echo "Creating $samples_file"
find "$outdir" -type f -name "*.fastq.gz"    \
    | sed -E 's|.*/||; s/_R[12]\.fastq.*//' \
    | sort -u > "$samples_file"

# Make checkpoint file
echo "Creating checkpoint."
mkdir -p checkpoints
touch "checkpoints/${prefix}.checkpoint"

# # MD5sums
# echo "Checking file copy integrity with MD5sum."
# # Run MD5sum on contents of $indir (if needed)
# if [[ -f "${indir}/md5sum" ]]
# then
#     echo "MD5sum detected in $indir"
# else
#     echo "Creating MD5sum in $indir"
#     while read -r file
#     do
#         md5sum "$file" >> "${indir}/md5sum"
#     done < "$og_file"
# fi
    
# # Run MD5sum on contents of $outdir (if needed)
# if [[ -f "${outdir}/md5sum" ]]
# then
#     echo "MD5sum detected in $outdir"
# else
#     echo "Creating MD5sum in $outdir"
#     for file in "${outdir}/"*.fastq.gz
#     do
#         md5sum "$file" >> "${outdir}/md5sum"
#     done
# fi

# # Verify that file contents are the same and create
# # $samples_file listing new sample IDs
# echo "Comparing MD5sum files."
# md5sum_test="test"
# if [[ -f "${indir}/md5sum" ]] && [[ -f "${outdir}/md5sum" ]]
# then
#     md5sum_test="$(comm -3 <(awk '{print $1}' "${indir}/md5sum" | sort) <(awk '{print $1}' "${outdir}/md5sum" | sort))"
# else
#     echo "Error - MD5sum files not created."
#     exit 1
# fi
# if [[ -z $md5sum_test ]]
# then
#     # Make $samples_file
#     echo "Creating $samples_file"
#     find "$outdir" -type f -name "*.fastq.gz" | sed 's/.*\///g' | sed 's/_R[12].fastq.*//g' | sort -u > "$samples_file"
#     # Make checkpoint file
#     echo "Creating checkpoint."
#     mkdir -p checkpoints
#     touch "checkpoints/${prefix}.checkpoint"
#     exit 0
# else
#     echo "Error - MD5sums don't match for:"
#     for md5 in $md5sum_test
#     do
#         grep "$md5" "${indir}/md5sum" "${outdir}/md5sum"
#     done
#     exit 1
# fi
