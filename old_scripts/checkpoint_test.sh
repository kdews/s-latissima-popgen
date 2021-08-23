# Define function to check for existence of a set of 
# similarly named checkpoint files with a wildcard

get_prefix () {
	local filename=`basename -- $1`
	local filename="${filename%.*}"
	echo $filename
}

checkpoints_exist () {
	if compgen -G "checkpoints/${1}*.checkpoint" > /dev/null
	then
		echo "true"
	else
		echo "false"
	fi
}
input_sbatch=$1
input_prefix=`get_prefix $input_sbatch`

if [[ `checkpoints_exist $input_prefix` == "true" ]]
then
	printf "If statement working\n"
else
	printf "If statement not working\n"
fi

until [[ `checkpoints_exist $input_prefix` == "true" ]]
do
	printf "Until loop working\n"
	sleep 2
done
printf "Until loop not working\n"
