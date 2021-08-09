import sys
#import numpy as np
import gzip
from collections import defaultdict

### takes list of bam with mark duplicates
### collapses the bams into a single bam when there are multiple bams


if len(sys.argv) < 2:
    print( "Usage: python " + sys.argv[0] + "list of bam files")
    sys.exit(0)

### identifies file name, strips extension
          
bam_files_and_fullpath = sys.argv[1]
bam_files_and_fullpath_no_ext = bam_files_and_fullpath.rsplit('.', 1)[0]

f=open(bam_files_and_fullpath, 'r')
lines=f.readlines()
f.close()

n = open("list_of_bam_files_ready_for_haplotyper.txt", 'w')


sample_with_bam_as_key = defaultdict(list)

for line in lines:
 full_path_and_bam = line.strip()
 print full_path_and_bam
 bam = full_path_and_bam.split("first_set/")[1]
 print bam
 full_path = full_path_and_bam.split("first_set/")[0] + "first_set/"
 print full_path
 sample_name = bam.split("_")[0]
 print sample_name

 sample_with_bam_as_key[sample_name].append(bam)
 
print sample_with_bam_as_key 

for key in sample_with_bam_as_key:
 print key
 print sample_with_bam_as_key[key]
 number_of_bams_to_collapse = len(sample_with_bam_as_key[key])
 print str(number_of_bams_to_collapse) + " test" 
 if 1 < int(number_of_bams_to_collapse):
  all_bams = " -I ".join(sample_with_bam_as_key[key])
  print "-I " + str(all_bams)
  collapse_bam_shell_script = str(key) + "_collapse_single_sample_bams.sh"
  g = open(collapse_bam_shell_script, 'w')
  g.write("#!/bin/bash" + "\n")
  g.write("#BATCH --cpus-per-task=12" + "\n")
  g.write("#SBATCH --time=100:00:00" + "\n")
  g.write("#SBATCH --mem=48000mb" + "\n")
  g.write("#SBATCH --partition cegs" + "\n")
  g.write("#SBATCH -o " + str(collapse_bam_shell_script) + ".out" + "\n")
  g.write("source activate hisat" + "\n") 
  ### change the directory of for writing files
  g.write("cd /scratch2/gmolano/seed_bank_variant_calling/first_set/" + "\n")
  g.write("java -jar /project/noujdine_61/gmolano/programs/gatk-4.1.2.0/gatk-package-4.1.2.0-local.jar MergeSamFiles -I " + str(all_bams) + " -O " +str(key) + "_merged_files_hisat2_CI_03_polished_filtered_scaffolded_marked_duplicates.bam" + "\n")
  remove_bams = " ".join(sample_with_bam_as_key[key])
  g.write("rm " + str(remove_bams))
  g.close()
  n.write(str(key) + "_merged_files_hisat2_CI_03_polished_filtered_scaffolded_marked_duplicates.bam" + '\n')
 else:
  n.write(str(sample_with_bam_as_key[key][0]) + '\n')
n.close()
