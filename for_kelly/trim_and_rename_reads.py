import sys
#import numpy as np
import gzip


if len(sys.argv) < 1:
    print( "Usage: python " + sys.argv[0] + "list of untrimmed fastq files and full path showing sample name and sequencing information")
    sys.exit(0)


### identifies file name, strips extension
          
untrimmed_reads_and_fullpath = sys.argv[1]
untrimmed_reads_and_fullpath_no_ext = untrimmed_reads_and_fullpath.rsplit('.', 1)[0]


f=open(untrimmed_reads_and_fullpath, 'r')
lines=f.readlines()
f.close()


for line in lines:
    sample_id = line.strip().split("/")[7]
    print sample_id
    fastq_1 = line.strip().split("/")[8]
    fastq_2 = str(fastq_1.split("1.fq.gz")[0]) + "2.fq.gz"
    print fastq_1
    print fastq_2
    some_path = line.strip().split("Clean/")[0]
    fullpath = str(some_path) + "Clean/" + str(sample_id) + "/"
    print fullpath
    shell_script = str(sample_id) + "_" + str(fastq_1) + "_fastp_shell.sh"
    g = open(shell_script, 'w')
    g.write("#!/bin/bash" + "\n")
    g.write("#BATCH --ntasks=12" + "\n")
    g.write("#SBATCH --time=100:00:00" + "\n")
    g.write("#SBATCH --mem=80000mb" + "\n")
    g.write("#SBATCH --partition cegs" + "\n")
    g.write("cd /scratch2/gmolano/seed_bank_variant_calling/trimmed_reads/first_set_trimmed" + "\n")
    g.write("source activate qc" + "\n")
    g.write("fastp --detect_adapter_for_pe --overrepresentation_analysis --correction --cut_right --thread 12 --html " + str(sample_id) + "_" + str(fastq_1) + ".fastp.html --json " + str(sample_id) + "_" + str(fastq_1) +"fastp.json -i " + str(fullpath) + "/" + str(fastq_1) + " -I " + str(fullpath) + "/" + str(fastq_2) + " -o " + str(sample_id) + "_" + str(fastq_1) + " -O " + str(sample_id) + "_" + str(fastq_2))
    g.close()
