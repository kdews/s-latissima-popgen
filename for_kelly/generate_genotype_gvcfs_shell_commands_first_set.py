import sys
#import numpy as np
import gzip

### list of gvcf files ready for genotype

if len(sys.argv) < 2:
    print( "Usage: python " + sys.argv[0] + "list of gvcf files ready for genotype")
    sys.exit(0)


### identifies file name, strips extension

gvcf_files = sys.argv[1]
gvcf_files_no_ext = gvcf_files.rsplit('.', 1)[0]


f=open(gvcf_files, 'r')
gvcf_lines=f.readlines()
f.close()


for line in gvcf_lines:
 gvcf = line.strip()
 gvcf_no_ext = gvcf.rsplit('.g.vcf.gz', 1)[0]
 print gvcf_no_ext
 g = open(str(gvcf_no_ext) + "_gatk4_gvcf_genotype.sh", 'w')
 g.write("#!/bin/bash" + "\n")
 g.write("#SBATCH --cpus-per-task=12" + "\n")
 g.write("#SBATCH --time=100:00:00" + "\n")
 g.write("#SBATCH --mem=48000mb" + "\n")
 g.write("#SBATCH --partition cegs" + "\n")
 g.write("#SBATCH -o " + str(gvcf) + "_gatk4_gvcf_genotype.out" + "\n")
 ### change the directory of for writing files
 g.write("cd /scratch2/gmolano/seed_bank_variant_calling/second_set" + "\n")
 g.write("source activate hisat" + "\n")
 g.write("java -jar /project/noujdine_61/gmolano/programs/gatk-4.1.2.0/gatk-package-4.1.2.0-local.jar GenotypeGVCFs -R /project/noujdine_61/kelp_data/hi_c_genomes/210416_CI_03_polished_filtered_scaffolded.fasta -V " + str(gvcf) + " -O " + str(gvcf_no_ext) + ".vcf.gz")
 g.close() 
