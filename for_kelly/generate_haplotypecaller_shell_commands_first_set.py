import sys
#import numpy as np
import gzip

### list of bams ready for haplotype caller (post-merge)

if len(sys.argv) < 2:
    print( "Usage: python " + sys.argv[0] + "list of bam files")
    sys.exit(0)

### identifies file name, strips extension
          
bam_files_and_fullpath = sys.argv[1]
bam_files_and_fullpath_no_ext = bam_files_and_fullpath.rsplit('.', 1)[0]


f=open(bam_files_and_fullpath, 'r')
lines=f.readlines()
f.close()


for line in lines:
 bam = line.strip()
 print bam
 
 sample_name = str(bam.split("_")[0])
 g = open(str(sample_name) + "_gatk4_haplotypecaller.sh", 'w')
 g.write("#!/bin/bash" + "\n")
 g.write("#BATCH --cpus-per-task=12" + "\n")
 g.write("#SBATCH --time=100:00:00" + "\n")
 g.write("#SBATCH --mem=48000mb" + "\n")
 g.write("#SBATCH --partition cegs" + "\n")
 g.write("#SBATCH -o " + str(sample_name) + "_gatk4_haplotypecaller.out" + "\n")
 ### change the directory of for writing files
 g.write("cd /scratch2/gmolano/seed_bank_variant_calling/first_set" + "\n")
 g.write("source activate samtools" + "\n")
 g.write("samtools index " + str(bam) + "\n")
 g.write("conda deactivate" + "\n") 
 g.write("source activate hisat" + "\n")
 g.write("java -jar /project/noujdine_61/gmolano/programs/gatk-4.1.2.0/gatk-package-4.1.2.0-local.jar HaplotypeCaller -R /project/noujdine_61/kelp_data/hi_c_genomes/210416_CI_03_polished_filtered_scaffolded.fasta -I " + str(bam) + " -O " + str(sample_name) + "_on_210416_CI_03.g.vcf.gz  -ERC GVCF -ploidy 1")


  

 
 g.close()
