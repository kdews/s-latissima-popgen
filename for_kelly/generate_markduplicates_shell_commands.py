import sys
#import numpy as np
import gzip

### input file is a sorted bam
### will use the Markduplicates from Picard
### end product - bam with marked duplicates ready for to combine bams before haplotype caller


if len(sys.argv) < 2:
    print( "Usage: python " + sys.argv[0] + "list of sorted bams files")
    sys.exit(0)

### identifies file name, strips extension
          
sorted_bam_files_and_fullpath = sys.argv[1]
sorted_bam_files_and_fullpath_no_ext = sorted_bam_files_and_fullpath.rsplit('.', 1)[0]


f=open(sorted_bam_files_and_fullpath, 'r')
lines=f.readlines()
f.close()


for line in lines:
 bam = line.strip().split("/")[5]
 print bam
 prefix = str(bam.split(".bam")[0])
 sample_name = prefix.split("_")[0]
 print sample_name
 sequencer = prefix.split("_")[1]
 print sequencer
 lane = prefix.split("_")[2]
 print lane
 index = prefix.split("_")[3]
 print index
 id = str(sequencer) + "." + str(lane)
 platform_unit = str(sequencer) + "." + str(lane) + "." + str(sample_name)
 platform_library = "ILLUMINA"
 library = str(sample_name) + "." + str(index)
 print id
 print platform_unit
 print platform_library
 print library
 path = line.strip().split(str(bam))[0]
 print path
 g = open(str(prefix) + "_markduplicates_shell_command.sh", 'w')
 g.write("#!/bin/bash" + "\n")
 g.write("#BATCH --cpus-per-task=12" + "\n")
 g.write("#SBATCH --time=100:00:00" + "\n")
 g.write("#SBATCH --mem=48000mb" + "\n")
 g.write("#SBATCH --partition cegs" + "\n")
 g.write("#SBATCH -o " + str(prefix) + "_mark_duplicates.out" + "\n")
 ### change the directory of for writing files
 g.write("cd /scratch2/gmolano/seed_bank_variant_calling/second_set" + "\n")
 g.write("source activate hisat" + "\n")
 g.write("java -jar /project/noujdine_61/gmolano/programs/gatk-4.1.2.0/gatk-package-4.1.2.0-local.jar MarkDuplicates -I " + str(prefix) + ".bam -O " + str(prefix) + "_marked_duplicates.bam -M " + str(prefix) + "_marked_dup_metrics.txt")


  

 
 g.close()
