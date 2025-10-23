import os
import re
import sys
import subprocess

# This script copies and renames all files in a folder to preferred format
# into a specified new directory.

## Files we want to rename are in the format:
## UniqueID_AmplificationType_Genus_species_SampleID_Plate_Barcode_Genus_Sequencer_Lane_Read.fastq.gz
## e.g.
## IZYN_NanoAmplified_Saccharina_angustissima_SA-CB-5-MG-3_1_GCAATGCA_Saccharina_I997_L1_R1.fastq.gz
## IZYN_NanoAmplified_Saccharina_angustissima_SA-CB-5-MG-3_1_GCAATGCA_Saccharina_I997_L1_R2.fastq.gz

## Some files (sequenced by machine I1018 or I1019) have a '_Number_' before SampleID
## Two sets of files are unique (the ones that contain 'LIS') and are handled as an exception
## e.g.
## JCGT_NanoAmplified_Saccharina__LIS-F1-3_3_TCTGTTGG_Saccharina_I1018_L1_R1.fastq.gz

## Renamed format:
## UniqueID_SampleID_Sequencer_Barcode_Plate_Lane_Read.fastq.gz

# Specify PATH to directory containing input files
og_file = sys.argv[1]
outdir = sys.argv[2]
rename_key = sys.argv[3]

print('Renaming...')
with open(og_file, 'r') as files:
	with open(rename_key, 'w') as changed_files:
		for file in files:
			file_stripped = os.path.basename(file.strip())
			file_list = file_stripped.rsplit('_')
			alts = ['I1018','I1019']
			if 'LIS' in file_stripped:
				uniqueid = file_list[0]
				sampleid = file_list[4]
				sequencer = file_list[8]
				plate = file_list[5]
				barcode = file_list[6]
				lane = file_list[9]
				read_fq = file_list[10]
			elif any(item in file_stripped for item in alts):
				uniqueid = file_list[0]
				sampleid = file_list[5]
				sequencer = file_list[9]
				plate = file_list[6]
				barcode = file_list[7]
				lane = file_list[10]
				read_fq = file_list[11]
			else:
				uniqueid = file_list[0]
				sampleid = file_list[4]
				sequencer = file_list[8]
				plate = file_list[5]
				barcode = file_list[6]
				lane = file_list[9]
				read_fq = file_list[10]
			newname = uniqueid + '_' + sampleid + '_' + sequencer + '_' + barcode + '_' + plate + '_' + lane + '_' + read_fq
			cmd = 'rsync ' + file.strip() + ' ' + outdir + '/' + newname
			print(cmd)
			os.system(cmd)
			changed_files.write(file + '\t' + outdir + '/' + newname + '\n')
		changed_files.close()
	files.close()

