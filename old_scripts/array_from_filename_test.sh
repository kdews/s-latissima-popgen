IN=`cat wgs/samples_file.txt`
for sample in $IN
do
	RGS=(${sample//_/ })
	echo "${RGS[1]}"
done
