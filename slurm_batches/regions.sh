#!/bin/bash

fwor=/project/noujdine_61/mkovalev/microbiome/variants

fres=${fwor}/vcf/regions
flog=${fwor}/logs
mkdir -p $fres $flog

lreg=${fwor}/config_regions.txt
cut -f 1 ${fwor}/reference/Macpyr2.fa.fai > $lreg

n_array=$(wc -l $lreg | sed "s/ .*$//g")
n_batch=100

# HARD SETUP
previous_jobid=476228

for (( start = 1; start < n_array; start += n_batch ))
do
  end=$(( start + n_batch - 1 ))
  if (( end >= n_array ))
  then
      end=$n_array
  fi

  arrays="--array=${start}-${end}"
  dependency="--dependency=afterok:$previous_jobid"
  log="--out=${flog}/gatk_regions_%03a.out"
  command="sbatch $arrays $dependency $log gatk_regions.job $fres $lreg"
  
  jobid=$($command | awk '{print $4}')
  previous_jobid=$jobid
done
