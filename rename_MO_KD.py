import os
import re
import sys
import subprocess

# This script copies and renames all files in a folder to preferred format
# into a specified new directory.

## Files we want to rename are in the format:
## Library_AmplificationType_Genus_species_SampleID_Plate_Barcode_Genus_RunID_Lane_Read.fastq.gz
## e.g.
## IZYN_NanoAmplified_Saccharina_angustissima_SA-CB-5-MG-3_1_GCAATGCA_Saccharina_I997_L1_R1.fastq.gz
## IZYN_NanoAmplified_Saccharina_angustissima_SA-CB-5-MG-3_1_GCAATGCA_Saccharina_I997_L1_R2.fastq.gz

## Some files (sequenced by machine I1018 or I1019) have a '_Number_' before SampleID
## Two sets of files are unique (the ones that contain 'LIS') and are handled as an exception
## e.g.
## JCGT_NanoAmplified_Saccharina__LIS-F1-3_3_TCTGTTGG_Saccharina_I1018_L1_R1.fastq.gz

## Renamed format:
## SampleID_Library_RunID_Barcode_Plate_Lane_Read.fastq.gz
## e.g.
## LIS-F1-3_JCGT_I1018_TCTGTTGG_3_L1_R1.fastq.gz

# Specify PATH to directory containing input files
og_file = sys.argv[1]
outdir = sys.argv[2]
rsync_list = sys.argv[3]

print('Renaming...')
with open(og_file, 'r') as files:
	with open(rsync_list, 'w') as cmd_list:
		for file in files:
			file_stripped = os.path.basename(file.strip())
			file_list = file_stripped.rsplit('_')
			alts = ['I1018','I1019']
			if 'LIS' in file_stripped:
				sampleid = file_list[4]
				library = file_list[0]
				runid = file_list[8]
				plate = file_list[5]
				barcode = file_list[6]
				lane = file_list[9]
				read_fq = file_list[10]
			elif any(item in file_stripped for item in alts):
				sampleid = file_list[5]
				library = file_list[0]
				runid = file_list[9]
				plate = file_list[6]
				barcode = file_list[7]
				lane = file_list[10]
				read_fq = file_list[11]
			else:
				sampleid = file_list[4]
				library = file_list[0]
				runid = file_list[8]
				plate = file_list[5]
				barcode = file_list[6]
				lane = file_list[9]
				read_fq = file_list[10]
			newname = sampleid + '_' + library + '_' + runid + '_' + barcode + '_' + plate + '_' + lane + '_' + read_fq
			# Write list of rsync commands (-c verifies file content)
			cmd = f'rsync -ac --progress {file.strip()} {os.path.join(outdir, newname)}\n'
			cmd_list.write(cmd)
		cmd_list.close()
	files.close()

