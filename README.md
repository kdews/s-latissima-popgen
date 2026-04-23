# Germline variant calling pipeline for North American kelp *Saccharina latissima*

## Run pipeline with your inputs
Script takes as input a genome and PATH to a directory containing FASTQs to align.
#### Usage
```
bash pipeline-s-latissima-popgen.sh [scripts_dir]
sbatch pipeline-s-latissima-popgen.sh [scripts_dir]

Options:
  -h/--help        print this usage message
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
### Notes
- Slurm scripts and logs are named with the convention:
  - `<prefix>.sbatch`: job submission script
  - `<prefix>.log`: non-array job logs
  - `<prefix>_logs/<prefix>_#.log`: array job logs
- Final genotyped VCFs are named: `<vcf_base>.vcf.gz`
  - vcf_base: `master_<year>_<ref>`
    - ref: reference FASTA filename base
```
  .
  ├── bam_stats_logs                  # Slurm log files for array job submission
  ├── bams
  |   ├── <ref>.fasta                                # reference genome (copied)
  |   ├── <ref>.fasta.ht2                             # indexed reference genome
  |   ├── <ref>.fasta.fai                    # samtools-indexed reference genome
  |   ├── <ref>.dict                   # GATK4-style reference genome dictionary
  |   ├── <sample_ID>_<ref>.sorted.bam               # initial sorted alignments
  |   └── <indiv_ID>_<ref>.sorted.marked.bam # final duplicate-marked alignments
  ├── bcftools_concat.log                                       # Slurm log file
  ├── bcftools_stats.log                                        # Slurm log file
  ├── checkpoints
  |   ├── <prefix>.checkpoint             # checkpoint for non-array job success
  |   └── <prefix>_<#>.checkpoint         # checkpoint for array (#) job success
  ├── collect_metrics_logs            # Slurm log files for array job submission
  ├── fastp_logs                      # Slurm log files for array job submission
  ├── fastqc_logs                     # Slurm log files for array job submission
  ├── gather_vcfs.log                                           # Slurm log file
  ├── genomicsdbimport
  |   └── interval_#                  # GATK4-style GenomicsDB for each interval
  ├── genomicsdbimport_logs           # Slurm log files for array job submission
  ├── genotype_gvcfs_logs             # Slurm log files for array job submission
  ├── gvcfs
  |   └── <indiv_ID>.g.vcf.gz         # per-indiviudal genome variant call files
  ├── haplotype_caller_logs           # Slurm log files for array job submission
  ├── hisat2_build.log                                          # Slurm log file
  ├── hisat2_logs                     # Slurm log files for array job submission
  ├── indexer                                                # indexes for input
  |   ├── samples_list.txt                                     # sample ID index
  |   ├── individuals_file.txt                             # individual ID index
  |   ├── intervals_list.txt                         # split interval list index
  |   ├── gvcf.sample_map                # GATK4-style sample map for gVCF files 
  |   └── vcf.list                     # index of VCF files (in numerical order)
  ├── mark_dupes_logs                 # Slurm log files for array job submission
  ├── multiqc.log                                               # Slurm log file
  ├── multiqc_data_<date>
  |   ├── multiqc_report_<date>_data                       # MultiQC report data
  |   └── multiqc_report_<date>.html                    # MultiQC report summary
  ├── prep_ref.log                                              # Slurm log file
  ├── quality_control                               # QC reports after each step
  |   ├── <sample_ID>_R#_fastqc.html                   # raw read FastQC reports
  |   ├── <sample_ID>_R#_fastqc.zip                       # raw read FastQC data
  |   ├── <sample_ID>_fastp.html                      # fastp trimming QC report
  |   ├── <sample_ID>_fastp.json                        # fastp trimming QC data
  |   ├── <sample_ID>_R#_fastp_fastqc.html         # trimmed read FastQC reports
  |   ├── <sample_ID>_R#_fastp_fastqc.zip             # trimmed read FastQC data
  |   ├── <sample_ID>_<ref>.hisat2.summary          # HISAT2 alignment QC report
  |   ├── <sample_ID>_<ref>.sorted.bam.validate.summary        # ValidateSamFile
  |   ├── <indiv_ID>_<ref>.marked_dup_metrics.txt      MarkDuplicates QC metrics
  |   ├── <indiv_ID>_<ref>.sorted.marked.bam.validate.summary  # ValidateSamFile
  |   ├── <indiv_ID>_<ref>.alignment_summary_metrics.txt # CollectAlignmentSummaryMetrics
  |   ├── <indiv_ID>_<ref>.read_length_histogram.pdf  # CollectAlignmentSummaryMetrics
  |   ├── <indiv_ID>_<ref>.collect_wgs_metrics.txt           # CollectWgsMetrics
  |   ├── <indiv_ID>_<ref>.insert_size_histogram.pdf  # CollectInsertSizeMetrics
  |   ├── <indiv_ID>_<ref>.insert_size_metrics.txt    # CollectInsertSizeMetrics
  |   ├── <indiv_ID>_<ref>.quality_yield_metrics.txt # CollectQualityYieldMetrics
  |   ├── <indiv_ID>_<ref>.stats    # samtools stats QC of final alignment files
  |   ├── <vcf_base>.bcftools.stats      # bcftools stats QC report of final VCF
  |   └── <vcf_base>.variant_eval.txt       # VariantEval QC report of final VCF
  ├── queen.log                                                   # pipeline log
  ├── rename.log                                                # Slurm log file
  ├── split_intervals
  |   └── ####-scattered.interval_list  # GATK4-style lists of genomic intervals
  ├── split_intervals.log                                       # Slurm log file
  ├── trim_galore_logs                # Slurm log files for array job submission
  ├── trimmed_reads
  |   └── <sample_ID>_R#_fastp.fastq.gz                 # reads trimmed by fastp
  ├── validate_sams-2_logs            # Slurm log files for array job submission
  ├── validate_sams_logs              # Slurm log files for array job submission
  ├── validate_variants-2_logs        # Slurm log files for array job submission
  ├── validate_variants-3.log         # Slurm log files for array job submission
  ├── validate_variants_logs          # Slurm log files for array job submission
  ├── variant_eval.log                                          # Slurm log file
  ├── vcfs
  |   ├── interval_#_<ref>.vcf.gz                        # VCFs at each interval
  |   └── <vcf_base>.vcf.gz          # final VCF combined over genomic intervals
  └── wgs
      └── <sample_ID>_R#.fastq.gz            # renamed paired-end reads (copied)
```

Direct any questions to Kelly DeWeese (kdeweese@mac.com)