array=(`cat wgs/samples_file.txt`)
array2=(`cat wgs_test/samples_file.txt`)

for index in ${!array[*]}
do 
	printf "Moving reads named ${array[$index]} to ${array2[$index]}.\n"
	a1_reads1=wgs/${array[$index]}_R1.fastq.gz
	a1_reads2=wgs/${array[$index]}_R2.fastq.gz
	a2_reads1=wgs/${array2[$index]}_R1.fastq.gz
	a2_reads2=wgs/${array2[$index]}_R2.fastq.gz
	mv $a1_reads1 $a2_reads1
	mv $a1_reads2 $a2_reads2
done
