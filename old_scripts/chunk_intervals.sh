#!/bin/bash


if [[ -f $genome ]]
then
	{ date; echo "Creating intervals file $intervals_file \
from $genome chromosome/scaffold IDs.";} \
>> $pipeline_log
	intervals_file=`grep ">" $genome | sed 's/>//g'`
else
	{ date; echo "Genome file $genome not found. Exiting...";} \
>> $pipeline_log
	exit 1
fi
if [[ -f $intervals_file ]]
then
	num_intervals=`cat $intervals_file | wc -l`
	array_size=$(( $num_intervals / $int_per_gvcf ))
	{ date; echo "Array size set to ${array_size}."; } \
>> $pipeline_log
	{ date; echo "Chunking $intervals_file into $array_size \
pieces in the directory ${interval_chunk_dir}..."; } >> $pipeline_log
	[[ -d $interval_chunk_dir ]] || mkdir $interval_chunk_dir
	chunk=1
	for i in `seq $int_per_gvcf $int_per_gvcf $num_intervals`
	do
		head -n${i} $intervals_file | tail -n${int_per_gvcf} > \
${interval_chunk_dir}/${chunk}_${intervals_file}
		((++chunk))
	done
	[[ -d ${interval_chunk_dir} ]] && \
[[ `ls ${interval_chunk_dir} | wc -l` -eq $array_size ]] && \
[[ `cat ${interval_chunk_dir}/* | sort` = \
`cat ${intervals_file} | sort` ]] && \
echo "Chunking successful." >> $pipeline_log || \
{ echo "Error - contents of ${interval_chunk_dir} files \
=/= ${intervals_file}." >> $pipeline_log; exit 1; }
else
        { date; echo "Error - $intervals_file not detected."; } \
>> $pipeline_log
        exit 1
fi
printspace
