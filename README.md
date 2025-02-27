# Germline variant calling pipeline for North American kelp *Saccharina latissima*

## Run pipeline with your inputs
Script takes as input a genome and PATH to a directory containing FASTQs to align.
#### Usage
```
sbatch pipeline_template.sh [options] <path/to/reference/genome> <path/to/dir/containing/FASTQs> <partition> [scripts_dir] [outdir]

Options:
  -h/--help                      print this usage message

Note: Sourced SBATCH files named with convention: <prefix>.sbatch 
```

## Pipeline steps
### Prepare and QC raw reads
1. Rename reads and create $samples_file
    - Before running, check if run has already succeeded.
    - Set dependency size for next step.
2. Repair FASTQs with BBMap's repair.sh
    - Depend start upon last job step.
    - Set dependency size for next step.
3. Remove original renamed reads to conserve memory before next steps
    - Depend start upon last job step.
4. Run FastQC on raw reads
    - Keep previous dependency.
    - Check for dependency jobid.
    - Set dependency size for next step.
5. Quality and adapter trimming
    - Depend start upon last job step.
    - Set dependency size for next step.

### Align reads to genome and QC alignment files
1. Run HISAT2-build on genome
    - Depend start upon last job step.
    - Redefine $genome location after HISAT2-build step.
2. Run HISAT2 on all samples
    - Depend start upon last job step.
    - Set dependency size for next step.
3. Sort IDs in $indiv_file for unique invidual IDs
4. Create reference genome dictionary and samtools index of genome for GATK tools
    - Depend start upon last job step.
    - Set dependency size for next step.
5. Run GATK4 ValidateSamFile on HISAT2 alignmnet BAMs
    - Depend start upon last job step.
    - Set dependency size for next step.
6. Run GATK4 CollectAlignmentSummaryMetrics on HISAT2 alignmnet BAMs
    - Depend start upon last job step.
    - Set dependency size for next step.
7. Run GATK4 CollectWgsMetrics on HISAT2 alignmnet BAMs
    - Depend start upon last job step.

### Process and QC alignment files
1. Run GATK4 MarkDuplicates
    - Depend start upon last job step.
    - Set dependency size for next step.
2. Run GATK4 ValidateSamFile on MarkDuplicate BAMs
    - Depend start upon last job step.
    - Set dependency size for next step.
3. Set new array size to number of individuals
4. Collapse BAMs per sample into BAMs per individual with GATK4 MergeSamFiles
    - Depend start upon last job step.
    - Set dependency size for next step.
5. Run GATK4 ValidateSamFile on MarkDuplicate BAMs
    - Depend start upon last job step.
    - Set dependency size for next step.
6. Index collapsed BAMs for GATK4 HaplotypeCaller
    - Depend start upon last job step.
    - Set dependency size for next step.

### Genotype and QC alignment files to generate per-sample gVCFs
1. Run GATK4 HaplotypeCaller
    - Depend start upon last job step.
    - Set dependency size for next step.
2. Create file to index HaplotypeCaller gVCFs
3. Run GATK4 ValidateVariants on HaplotypeCaller gVCFs
    - Depend start upon last job step.
    - Set dependency size for next step.

### Combine per-sample gVCFs and resplit by genomic region into per-interval gVCFs
1. Run GATK4 SplitIntervals on genome to produce interval lists in $split_intervals_dir for GenomicsDBImport step
    - Depend start upon last job step.
    - Set dependency size for next step.
2. Set array size to number of split interval lists created
3. Create file to index split intervals lists
4. Run GATK4 GenomicsDBImport
    - Depend start upon last job step.
    - Set dependency size for next step.

### Call variants on and QC per-interval gVCFs to generate per-interval VCFs
1. Run GATK4 GenotypeGVCFs
    - Depend start upon last job step.
    - Set dependency size for next step.
2. Create list of per-interval VCFs
3. Run GATK4 SortVcf on GenotypeGVCFs VCFs
    - Depend start upon last job step.
    - Set dependency size for next step.
4. Overwrite index of VCF files with sorted index
    - Depend start upon last job step.
5. Run GATK4 ValidateVariants on GenotypeGVCFs VCFs
    - Depend start upon last job step.
    - Set dependency size for next step.

### Merge per-interval VCFs into final VCF
1. Run GATK4 MergeVcfs
    - Depend start upon last job step.

## Output
### Analysis
```
  indexer/
    samples_file.txt             indexes sample IDs
    individuals_file.txt         indexes individual IDs
    intervals_file.txt           indexes split interval lists
    gvcf.list                    indexes gVCF files 
    vcf.list                     indexes VCF files (in numerical order)
  wgs/                        
    *.fastq.gz                   FASTQ files renamed to shorter sample IDs 
                                 (copied from source)
    *.repaired.fastq.gz          FASTQ read pairs repaired with repair.sh
  trimmed_reads/
    *_val_1/2.fq.gz              reads post trimming by Trim Galore!
  bams/
    *.fasta                      reference genome (copied from source)
    *.fasta.ht2                  indexed reference genome
    *.fasta.fai                  samtools-indexed reference genome
    *.dict                       GATK4-style reference genome dictionary
    *.sorted.bam                 sorted alignment files of trimmed reads to 
                                 reference genome
    *.sorted.marked.bam          sorted alignment files, duplicates marked
    *.sorted.marked.merged.bam   sorted alignment files, merged by individual
  gvcfs/
    *.g.vcf.gz                   genome variant call files (gVCFs) for each 
                                 individual
  split_intervals/
    *-scattered.interval_list    GATK4-style lists of genomic intervals, split 
                                 into as close to the desired scatter count as 
                                 possible without splitting input reference 
                                 contigs (e.g., scaffolds/chromosomes)
  genomicsdbimport/
    interval_*/                  GATK4-style GenomicsDB (datastore of variant
                                 call data from each individual, split into 
                                 groups of genomic intervals specified in 
                                 *-scattered.interval_list files)
  vcfs/
    *.vcf.gz                     variant call files (VCFs) for each group of 
                                 genomic intervals
  master_{genome_base}.vcf.gz    final VCF file of all samples aligned to the
                                 reference genome
```

### Quality control
```
  quality_control/
    *_fastqc.zip/html            FastQC reports for all input FASTQs
    *_val_1/2_fastqc.zip/html    FASTQC reports for trimmed FASTQs
    *_trimming_report.txt        Trim Galore! trimming report for each sample
    *.hisat2.summary             HISAT2 alignment report for each sample
    *.validate.summary           validation reports of alignment (SAM/BAM) and 
                                 variant (gVCF/VCF) files
    multiqc_report.html          MultiQC report summarizing QCs at each step
```

### Logs and checkpoints
```
  queen.log                      log file generated by pipeliner script
  <prefix>_logs/
    <prefix>_<#>.out             SLURM log files from inividual job step 
                                 submissions, named with the convention: 
                                 <prefix>.sbatch > 
                                 <prefix>_logs/<prefix>_<#>.out 2>&1
                                 created upon job completion, where #
                                 corresponds to array index of <prefix> job step
  checkpoints/
    <prefix>_<#>.checkpoint      checkpoint file(s) for each job step, named 
                                 with the convention: 
                                 <prefix>.sbatch == <prefix>_<#>.checkpoint
                                 created upon job completion, where # 
                                 corresponds to array index of <prefix> job step
```

### Temporary directories
```
  <prefix>_tmp                   temporary directory for a given job step
```

Direct any questions to Kelly DeWeese (kdeweese@mac.com)