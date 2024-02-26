#!/usr/bin/env python
'''
# Copyright 2013-2014 Mirsk Digital Aps  (Author: Andreas Kirkedal)

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0

# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

'''
from __future__ import print_function


import sys
import codecs
import os
import shutil
from sprakparser import Session

n = 0


### Utility functions
def find_ext_folders(topfolder, extfolderlist, file_ext):
    '''Recursive function that finds all the folders containing $file_ext files
    and returns a list of folders.'''

    for path in os.listdir(topfolder):
        curpath = os.path.join(topfolder, path)
        if os.path.isdir(curpath):
            find_ext_folders(curpath, extfolderlist, file_ext)
        elif os.path.isfile(curpath):
            if os.path.splitext(path)[1] == file_ext:
                extfolderlist.append(topfolder)
                return
        else:
                pass


def create_parallel_file_list(session, sndlist, txtlist, max_recordings):
    '''This function creates two lists that are aligned line by line and a text file. 
    The two lists are aligned line by line. One list contains the locations of a sound
    file, the other list contains the location of a text file that contains the
    transcription for that sound file. The text file is output by this function, but
    to save disk space, the sound file remains where it is.'''
    if max_recordings == 0:
        return 0

    shadow = False
    if os.path.exists(session.sessiondir):  # The dir exists, i.e. the sessiondir name is not unique

        # Append counter to create new directory. Use global counter to prevent resetting every time
        # the function is called.
        if len(os.listdir(session.sessiondir)) != 0:  # Check if there are files in the directory
            global n
            n += 1
            session.sessiondir = "{}_{}".format(session.sessiondir, n)
            session.speaker_id = "{}_{}".format(session.speaker_id, n)
            os.mkdir(session.sessiondir)
            shadow = True
    else:
        os.mkdir(session.sessiondir)

    count = 0
    for recnum, recording in enumerate(session.record_states):
        #print(session.record_states)
        if recnum == 0:     # skip the first recording of silence
            # print("Ignore silence")
            continue
        oldsound = os.path.join(session.wavdir, recording[1])

        # Some wavdirs are empty, check for files
        if not os.path.exists(oldsound): 
            # print("Could not find %s" % oldsound)
            continue

        # create file and write the transcription
        txtout = session.create_filename(recnum+1, "txt")
        txtline = os.path.join(session.sessiondir, txtout)
        fout = codecs.open(txtline, "w", "utf8")
        fout.write(recording[0] + "\n")   
        fout.close()

        # write locations to lists
        # "791213 8232-r4670118-2" has a space. Not good.
        txtline = txtline.replace('791213 8232', '791213_8232')
        oldsound = oldsound.replace('791213 8232', '791213_8232')
        txtlist.write(txtline + "\n")  # write lists of txt files
        sndlist.write(oldsound + "\n")   # write lists of recordings

        count += 1

        if count >= max_recordings:
            print("Skipping %d recordings (%.1f%%)" % (
                len(session.record_states) - count - 1,
                100.0 * (len(session.record_states) - count - 1) / (len(session.record_states) - 1)))
            break # Only |max_recordings| recordings per session

    if count == 0:
        # Nothing useful in this spl file. Delete it
        # to save ourselves time and effort next time
        print("Deleting useless spl file %s" %
              session.source)
        os.unlink(session.source)
        
    
    # if recnum == 10:
    #     sys.exit('Are there files?')

    if len(os.listdir(session.sessiondir)) == 0:  # Remove dir if it is empty
        os.rmdir(session.sessiondir)
        if shadow:
            n -= 1
            shadow = False

    return count


def make_speech_corpus(top, dest, txtdest, snddest, srcfolder, limit=None):
    '''This function tests whether the information in an spl file is sufficient to
    extract the recording and text. It also creates a directory name based on the
    speaker id and the sessions id for the processed files.'''

    if limit is None:
        limit = 9999999
    count = 0
    spls = os.listdir(srcfolder)
    for splfile in sorted(spls):
        if os.path.splitext(splfile)[1] != ".spl":
            continue
        print(top, srcfolder, splfile, limit)

        # Parse the spl file and check whether key information has been found.
        # This is necessary because not all files are complete, some contain errors
        # from maual editing and some spl files point to recordings that do not
        # exit in the corpus
        session = Session(os.path.abspath(srcfolder), splfile)
        if not session.wavdir:  # ignore if there is no matching directory
            print("No wav directory")
            # Delete to save ourselves wasted time in the future.
            os.unlink(session.wavdir)
            continue
        if session.speaker_id == "":  # ignore if there is no speaker
            print("No speaker")
            continue
        if len(session.record_states) < 2:  # unsure whether this has an effect
            print("Only %d record_states" % len(session.record_states))
            continue
        session.sessiondir = os.path.join(dest, session.filestem) + "." + session.speaker_id

        if count >= limit:
            print("Ran into the limit of number of recordings.")
            break
        #
        used_recording_count = create_parallel_file_list(session, snddest, txtdest, limit - count)
        print("Used %d recordings" % used_recording_count)
        count += used_recording_count

    return count

if __name__ == '__main__':
    try:
        topfolder = sys.argv[1]
        dest = sys.argv[2]
    except:
        print('Usage: python3 sprak2kaldi.py <corpus project dir> <processed corpus project subdir>')
        print('E.g. python3 sprak2kaldi.py /path/to/data/local/data/0565-1  /path/to/data/local/data/corpus_processed/0565-1' )
        sys.exit('exit 1')

    if os.path.exists(dest):
        try:
            shutil.rmtree(dest)
            os.mkdir(dest)
        except:
            print('Failed to remove ' + dest)
            sys.exit('Must remove ' + dest + ' to proceed corpus preparation.')
        

    ## Find the subdirectories containing '.spl' files. These files contain information that
    #  pairs a recording with speaker information, id and script
    spldirs = []
    find_ext_folders(topfolder, spldirs, ".spl")

    sndlist = codecs.open(os.path.join(dest, "sndlist"), "w", "utf8")
    txtlist = codecs.open(os.path.join(dest, "txtlist"), "w", "utf8")



    limit = 10000
    for num, folder in enumerate(spldirs):
        if limit == 0:
            break
        recordings_count = make_speech_corpus(topfolder, dest, txtlist, sndlist, folder, limit)
        limit -= recordings_count

    sndlist.close()
    txtlist.close()
