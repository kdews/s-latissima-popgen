import os

logdir="rename_logs"

if os.path.isfile(logdir + '/rename.log') and os.path.isfile(logdir + '/original_filenames.txt'):
    print('Restarting run based on contents of ' + logdir + '/rename.log.')
    with open(logdir + '/original_filenames.txt','r') as files:
        with open(logdir + '/rename.log', 'r') as previous_changed_files:
            with open(logdir + '/rename_restart.log', 'w') as changed_files:
                for filename, prev_change in zip(files, previous_changed_files):
                    file_stripped = os.path.basename(filename.strip())
                    prev_change=prev_change.strip()
                    if file_stripped in prev_change:
                        print(file_stripped, 'detected in new directory.', sep=' ')
                        changed_files.write(prev_change)
                        continue
