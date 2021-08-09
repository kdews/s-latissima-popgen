import sys
#import numpy as np
import gzip

### list of gvcf files ready for combine and list of intervals to combine on

if len(sys.argv) < 3:
    print( "Usage: python " + sys.argv[0] + "list of gvcf files ready for combine and list of intervals to combine on")
    sys.exit(0)


### identifies file name, strips extension

gvcf_files = sys.argv[1]
gvcf_files_no_ext = gvcf_files.rsplit('.', 1)[0]

intervals = sys.argv[2]
intervals_no_ext = intervals.rsplit('.', 1)[0]

f=open(gvcf_files, 'r')
gvcf_lines=f.readlines()
f.close()

j=open(intervals, 'r')
interval_lines=j.readlines()
j.close()

for line in interval_lines:
 interval = line.strip()
 print interval
 g = open(str(interval) + "_gatk4_gvcf_combine.sh", 'w')
 g.write("#!/bin/bash" + "\n")
 g.write("#SBATCH --cpus-per-task=12" + "\n")
 g.write("#SBATCH --time=100:00:00" + "\n")
 g.write("#SBATCH --mem=48000mb" + "\n")
 g.write("#SBATCH --partition cegs" + "\n")
 g.write("#SBATCH -o " + str(interval) + "_gatk4_gvcf_combine.out" + "\n")
 ### change the directory of for writing files
 g.write("cd /scratch2/gmolano/seed_bank_variant_calling/first_set" + "\n")
 g.write("source activate hisat" + "\n")
 g.write("java -jar /project/noujdine_61/gmolano/programs/gatk-4.1.2.0/gatk-package-4.1.2.0-local.jar CombineGVCFs -R /project/noujdine_61/kelp_data/hi_c_genomes/210416_CI_03_polished_filtered_scaffolded.fasta --intervals " + str(interval) + " ")
 for line in gvcf_lines:
  gvcf = line.strip()
  g.write("--variant " + str(gvcf) + " ")
 g.write("-O " + str(interval) + "_second_set_gk_seed_bank_on_CI_03.g.vcf.gz")
 g.close() 
