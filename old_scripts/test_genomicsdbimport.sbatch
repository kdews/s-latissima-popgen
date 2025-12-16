#!/bin/bash
#SBATCH -J test_genomicsdbimport
#SBATCH -o %x.log
#SBATCH --time=1-0
#SBATCH --mem=50g
#SBATCH --cpus-per-task=9

# Load GATK4
module purge
module load gcc/13.3.0 gatk/4.5.0.0 python/3.13.2 openjdk/21.0.0_35
gatk --version || exit 1

# Define memory for GATK4 (leave more for $TMPDIR cache)
# Minimum = 20% of memory
gatk_mem_min="$(( 2 * SLURM_MEM_PER_NODE / 10 ))M"
# Maximum = 30% of memory
gatk_mem_max="$(( 3 * SLURM_MEM_PER_NODE / 10 ))M"
# Allocate threads for gVCF reader
reader_threads="$(( SLURM_CPUS_PER_TASK - 1 ))"

# Run GATK4's GenomicsDBImport
cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  GenomicsDBImport
  -R bams/SlaSLCT1FG3_1_AssemblyScaffolds_Repeatmasked.fasta
  --sequence-dictionary bams/SlaSLCT1FG3_1_AssemblyScaffolds_Repeatmasked.dict
  -L scaffold_4497
  # Give TMPDIR environment variable (Slurm sets this)
  --tmp-dir "$TMPDIR"
  --sample-name-map indexer/test.sample_map
  --genomicsdb-workspace-path genomicsdbimport/test_interval
  --reader-threads "$reader_threads"
  --genomicsdb-shared-posixfs-optimizations
)
echo "${cmd[*]}"
"${cmd[@]}"

# Run GATK4's GenotypeGVCFs with GenomicsDBImport option
geno_cmd=(
  gatk
  --java-options "-Xms$gatk_mem_min -Xmx$gatk_mem_max"
  GenotypeGVCFs
  -ploidy 1
  -R bams/SlaSLCT1FG3_1_AssemblyScaffolds_Repeatmasked.fasta
  --sequence-dictionary bams/SlaSLCT1FG3_1_AssemblyScaffolds_Repeatmasked.dict
  -L scaffold_4497
  -V gendb://genomicsdbimport/test_interval
  -O vcfs/test.vcf
  # Give TMPDIR environment variable (Slurm sets this)
  --tmp-dir "$TMPDIR"
  --genomicsdb-shared-posixfs-optimizations
  --verbosity DEBUG
)
echo "${geno_cmd[*]}"
"${geno_cmd[@]}"
