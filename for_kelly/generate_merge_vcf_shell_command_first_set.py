import sys
#import numpy as np
import gzip

### list of gvcf files ready for genotype

if len(sys.argv) < 2:
    print( "Usage: python " + sys.argv[0] + "list of vcf files ready for merge")
    sys.exit(0)


### identifies file name, strips extension

vcf_files = sys.argv[1]
vcf_files_no_ext = vcf_files.rsplit('.', 1)[0]


f=open(vcf_files, 'r')
vcf_lines=f.readlines()
f.close()

g = open("first_set_gatk_vcf_merge.sh", 'w')
g.write("#!/bin/bash" + "\n")
g.write("#SBATCH --cpus-per-task=12" + "\n")
g.write("#SBATCH --time=100:00:00" + "\n")
g.write("#SBATCH --mem=48000mb" + "\n")
g.write("#SBATCH --partition cegs" + "\n")
g.write("#SBATCH -o " + str(vcf_files_no_ext) + "_gatk4_vcf_merge.out" + "\n")
### change the directory of for writing files
g.write("cd /scratch2/gmolano/seed_bank_variant_calling/first_set" + "\n")
g.write("source activate hisat" + "\n")

g.write("java -jar /project/noujdine_61/gmolano/programs/gatk-4.1.2.0/gatk-package-4.1.2.0-local.jar MergeVcfs ")

for line in vcf_lines:
 vcf = line.strip()
 vcf_no_ext = vcf.rsplit('.vcf.gz', 1)[0]
 print vcf_no_ext
 g.write("-I " + str(vcf) + " ")

g.write("-O first_set_raw_241_indv_on_CI_03.vcf.gz")
g.close() 
