# Germline variant calling pipeline for North American kelp *Saccharina latissima*

## Run pipeline with your inputs
Script takes as input a genome and PATH to a directory containing FASTQs to align.
#### Usage
```
sbatch pipeline_template.sh [options] <path/to/reference/genome> <path/to/dir/containing/FASTQs> <partition> [scripts_dir] [outdir]

Options:
  -h/--help                      print this usage message
```

## Pipeline steps
### Prepare and QC raw reads
1. Rename reads and create list of sample IDs ([rename.sbatch](rename.sbatch))
2. Repair FASTQs with [BBMap's repair.sh](https://github.com/BioInfoTools/BBMap/blob/master/sh/repair.sh) ([repair.sbatch](repair.sbatch))
3. Remove original renamed reads to conserve memory before next steps
```
for sample_id in $(cat $samples_file)
do
  if [[ -f ${samples_dir}/${sample_id}_R1.fastq.gz ]] && [[ -f ${samples_dir}/${sample_id}_R2.fastq.gz ]] && [[ -f ${trimmed_dir}/${sample_id}_R1.repaired.fastq.gz ]] && [[ -f ${trimmed_dir}/${sample_id}_R2.repaired.fastq.gz ]]
  then
    rm ${samples_dir}/${sample_id}_R1.fastq.gz
    rm ${samples_dir}/${sample_id}_R2.fastq.gz
  fi
done
```
4. Run [FastQC](https://www.bioinformatics.babraham.ac.uk/projects/fastqc/) on raw reads ([fastqc.sbatch](fastqc.sbatch))
5. Quality- and adapter-trim raw reads with [Trim Galore!](https://www.bioinformatics.babraham.ac.uk/projects/trim_galore/) ([trim_galore.sbatch](trim_galore.sbatch))

### Align reads to genome
5. Run [HISAT2-build](https://daehwankimlab.github.io/hisat2/manual/) on genome ([build_hisat2.sbatch](build_hisat2.sbatch))
    - Redefine genome path after HISAT2-build step.
```
genome=${bams_dir}/${genome_basename_unzip}
```
6. Run [HISAT2](https://daehwankimlab.github.io/hisat2/manual/) on all samples ([hisat2.sbatch](hisat2.sbatch))
    - Script will iteratively save parsed sample IDs to list of individual IDs (```$indiv_file```).
7. Filter to keep only unique individaul IDs in list ([]())
```
sort -u $indiv_file > ${indiv_file}_sorted
mv ${indiv_file}_sorted $indiv_file
```
8. Create reference genome dictionary and samtools index of genome for GATK tools ([prep_ref.sbatch](prep_ref.sbatch))

### QC alignment files
9. Run GATK4 ValidateSamFile on HISAT2 alignmnet BAMs ([validate_sams.sbatch](validate_sams.sbatch))
10. Run GATK4 CollectAlignmentSummaryMetrics on HISAT2 alignmnet BAMs ([collect_alignment_summary_metrics.sbatch](collect_alignment_summary_metrics.sbatch))
11. Run GATK4 CollectWgsMetrics on HISAT2 alignmnet BAMs ([collect_wgs_metrics.sbatch](collect_wgs_metrics.sbatch))

### Process and QC alignment files
12. Run GATK4 MarkDuplicates ([mark_dupes.sbatch](mark_dupes.sbatch))
13. Run GATK4 ValidateSamFile on MarkDuplicate BAMs ([validate_sams.sbatch](validate_sams.sbatch))
14. Set new array size to number of individuals
```
num_indiv=$(cat $indiv_file | wc -l)
array_size=$num_indiv
```
15. Collapse per-sample BAMs into per-individual BAMs with GATK4 MergeSamFiles ([collapse_bams.sbatch](collapse_bams.sbatch))
16. Run GATK4 ValidateSamFile on per-individual BAMs ([validate_sams.sbatch](validate_sams.sbatch))
17. Index per-individual BAMs for GATK4 HaplotypeCaller ([index_bams.sbatch](index_bams.sbatch))

### Genotype and QC alignment files to generate per-sample gVCFs
18. Run GATK4 HaplotypeCaller ([haplotype_caller.sbatch](haplotype_caller.sbatch))
19. Create file to index HaplotypeCaller gVCFs
```
ls $gvcfs_dir/*g.vcf.gz > $gvcf_list
```
20. Run GATK4 ValidateVariants on HaplotypeCaller gVCFs ([validate_variants.sbatch](validate_variants.sbatch))

### Combine per-sample gVCFs and resplit by genomic region into per-interval gVCFs
21. Run GATK4 SplitIntervals on genome to produce interval lists in ```split_intervals/``` for GenomicsDBImport step ([split_intervals.sbatch](split_intervals.sbatch))
22. Set array size to number of split interval lists created
```
array_size=$(( $(ls ${split_intervals_dir}/*list | wc -l) ))
```
23. Create file to index split intervals lists
```
ls ${split_intervals_dir}/*list > $intervals_file
```
24. Run GATK4 GenomicsDBImport ([genomicsdbimport.sbatch](genomicsdbimport.sbatch))

### Call variants on and QC per-interval gVCFs to generate per-interval VCFs
25. Run GATK4 GenotypeGVCFs ([genotype_gvcfs.sbatch](genotype_gvcfs.sbatch))
26. Create list of per-interval VCFs
```
ls $vcfs_dir/*${genome_base}.vcf.gz > $vcf_list
```
27. Run GATK4 SortVcf on GenotypeGVCFs VCFs ([sort_vcf.sbatch](sort_vcf.sbatch))
28. Overwrite index of VCF files with sorted index
```
ls $vcfs_dir/*${genome_base}.sorted.vcf.gz > $vcf_list
```
29. Run GATK4 ValidateVariants on GenotypeGVCFs VCFs ([validate_variants.sbatch](validate_variants.sbatch))

### Merge per-interval VCFs into final VCF
30. Run GATK4 MergeVcfs ([merge_vcfs.sbatch](merge_vcfs.sbatch))

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