#!/bin/bash
#SBATCH --mem=8gb
#SBATCH --time=03:00:00

datadir=$1
outdir=$2
logdir=rename_logs
samples_file=$3
# Optional, to specify directory containing scripts
scripts_dir=$4/

# Create new output directory (if needed)
if [[ ! -d $outdir ]]
then
	printf "Creating output directory ${outdir}.\n\n"
	mkdir $outdir 
fi

# Run rename Python script
python ${scripts_dir}rename_MO_KD.py $datadir $outdir $logdir
# Exit with error code on Python failure
if [[ $? -ne 0 ]]
then
	printf "Error on Python script submission.\n"
	exit 1
fi

# MD5SUMs
# Run md5sum on contents of $datadir
if [[ -f ${datadir}/md5sum ]]
then
	rm ${datadir}/md5sum
fi
for file in `ls ${datadir}/*fastq.gz`
do
	md5sum $file >> ${datadir}/md5sum
done
# Run md5sum on contents of $outdir
if [[ -f ${outdir}/md5sum ]]
then
	rm ${outdir}/md5sum
fi
for file in `ls ${outdir}/*fastq.gz`
do
	md5sum $file >> ${outdir}/md5sum
done

# Verify that file contents are the same and create
# $samples_file listing new sample IDs
md5sum_test=`comm -3 \
<(awk '{print $1}' ${path_to_reads}/md5sum | sort) \
<(awk '{print $1}' ${samples_dir}/md5sum | sort)`
if [[ -z $md5sum_test ]]
then
	ls ${outdir} | sed 's/_R[12].fastq.*//g' \
| sort -u > $samples_file
	if [[ $? -eq 0 ]]
	then
		if [[ ! -d checkpoints ]]
		then
			mkdir checkpoints
		fi
		touch checkpoints/rename.checkpoint
		exit 0
	fi
else
	printf "Error - the following renamed file \n\
contents are not identical according to MD5SUM:\n"
	for md5 in $md5sum_test
	do
		grep "$md5" ${path_to_reads}/md5sum \
${samples_dir}/md5sum
	done
	exit 1
fi
