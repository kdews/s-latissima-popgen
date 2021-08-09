import os,re,sys,subprocess

# This script renames all files in a folder to preferred format.

## Files we want to rename are in the format:
## UniqueID_AmplificationType_Genus_species_SampleID_Plate_Barcode_Genus_Sequencer_Lane_Read.fastq.gz
## e.g.
## IZYN_NanoAmplified_Saccharina_angustissima_SA-CB-5-MG-3_1_GCAATGCA_Saccharina_I997_L1_R1.fastq.gz
## IZYN_NanoAmplified_Saccharina_angustissima_SA-CB-5-MG-3_1_GCAATGCA_Saccharina_I997_L1_R2.fastq.gz

## Some files (sequenced by machine I1018 or I1019) have a "_Number_" before SampleID
## Two sets of files are unique (the ones that contain "LIS") and are handled as an exception
## e.g.
## JCGT_NanoAmplified_Saccharina__LIS-F1-3_3_TCTGTTGG_Saccharina_I1018_L1_R1.fastq.gz

## Renamed format:
## SampleID_Sequencer_Plate_Lane_Read.fastq.gz

print("Creating list of all FASTQs in folder...")
cmd = "ls *fastq.gz > original_filenames.txt"
os.system(cmd)

print("Renaming...")

with open('original_filenames.txt','r') as files:
    with open('rename_MO_KD.log', 'w') as changed_files:
        for file in files:
            file_stripped = file.strip()
            alts = ['I1018','I1019']
            if 'LIS' in file_stripped:
                sampleid = file_stripped.rsplit('_')[4]
                sequencer = file_stripped.rsplit('_')[8]
                plate = file_stripped.rsplit('_')[5]
                lane = file_stripped.rsplit('_')[9]
                read_fq = file_stripped.rsplit('_')[10]
            elif any(item in file_stripped for item in alts):
                sampleid = file_stripped.rsplit('_')[5]
                sequencer = file_stripped.rsplit('_')[9]
                plate = file_stripped.rsplit('_')[6]
                lane = file_stripped.rsplit('_')[10]
                read_fq = file_stripped.rsplit('_')[11]
            else:
                sampleid = file_stripped.rsplit('_')[4]
                sequencer = file_stripped.rsplit('_')[8]
                plate = file_stripped.rsplit('_')[5]
                lane = file_stripped.rsplit('_')[9]
                read_fq = file_stripped.rsplit('_')[10]
            newname = sampleid + '_' + sequencer + '_' + lane + '_' + read_fq
            print('Converting', file_stripped, 'to', newname, sep=' ')
            changed_files.write(file_stripped + '\t' + newname + '\n')
            cmd = 'mv ' + file_stripped + ' ' + newname
            os.system(cmd)
        changed_files.close()
    files.close()

os.system('rm original_filenames.txt')


