import sys
#import numpy as np
import gzip

### specifically will align to 210416_CI_03_polished_filtered_scaffolded.fasta


if len(sys.argv) < 2:
    print( "Usage: python " + sys.argv[0] + "list of trimmed fastq files")
    sys.exit(0)

### identifies file name, strips extension
          
trimmed_reads_and_fullpath = sys.argv[1]
trimmed_reads_and_fullpath_no_ext = trimmed_reads_and_fullpath.rsplit('.', 1)[0]


f=open(trimmed_reads_and_fullpath, 'r')
lines=f.readlines()
f.close()


for line in lines:
 fastq_1 = line.strip().split("/")[6]
 print fastq_1
 fastq_2 = str(fastq_1.split("_1.fq.gz")[0]) + "_2.fq.gz"
 print fastq_2
 prefix = str(fastq_1.split("_1.fq.gz")[0])
 sample_name = fastq_1.split("_")[0]
 print sample_name
 sequencer = fastq_1.split("_")[1]
 print sequencer
 lane = fastq_1.split("_")[2]
 print lane
 index = fastq_1.split("_")[3]
 print index
 id = str(sequencer) + "." + str(lane)
 platform_unit = str(sequencer) + "." + str(lane) + "." + str(sample_name)
 platform_library = "ILLUMINA"
 library = str(sample_name) + "." + str(index)
 print id
 print platform_unit
 print platform_library
 print library
 path = line.strip().split(str(fastq_1))[0]
 print path
 g = open(str(prefix) + "_hisat2_shell_command.sh", 'w')
 g.write("#!/bin/bash" + "\n")
 g.write("#BATCH --cpus-per-task=12" + "\n")
 g.write("#SBATCH --time=100:00:00" + "\n")
 g.write("#SBATCH --mem=48000mb" + "\n")
 g.write("#SBATCH --partition cegs" + "\n")
 g.write("source activate hisat" + "\n")
 g.write("cd /scratch2/gmolano/seed_bank_variant_calling/testing_different_aligners/hisat2/" + "\n")
 g.write("hisat2 -p 12 -x /project/noujdine_61/kelp_data/hi_c_genomes/210416_CI_03_polished_filtered_scaffolded -q -1 " + str(path) + str(fastq_1) + " -2 " + str(path) + str(fastq_2) + " --rg-id=" + str(id) + " --rg PU:" + str(platform_unit) + " --rg SM:" + str(sample_name) + " --rg LB:" + str(library) + " --rg PL:ILLUMINA --summary-file " + str(prefix) + ".summary -S " + str(prefix) + "_hisat2_CI_03_polished_filtered_scaffolded.sam")
 g.close()
