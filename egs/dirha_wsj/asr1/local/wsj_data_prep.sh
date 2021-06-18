#!/usr/bin/env bash

# Copyright 2009-2012  Microsoft Corporation  Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0.

# Modified from the script for dirha_wsj
# Xiaofei Wang 06/01/2019

if [ $# -le 3 ]; then
   echo "Arguments should be a list of WSJ directories, see ../run.sh for example."
   exit 1;
fi


dir=`pwd`/data/local/data
lmdir=`pwd`/data/local/nist_lm
mkdir -p $dir $lmdir
local=`pwd`/local
utils=`pwd`/utils

. ./path.sh # Needed for KALDI_ROOT
sph2pipe=sph2pipe
if ! command -v "${sph2pipe}" &> /dev/null; then
  echo "Could not find (or execute) the sph2pipe program at $sph2pipe";
  exit 1;
fi

if [ -z $IRSTLM ] ; then
  export IRSTLM=$KALDI_ROOT/tools/irstlm/
fi
export PATH=${PATH}:$IRSTLM/bin
if ! command -v prune-lm >/dev/null 2>&1 ; then
  echo "$0: Error: the IRSTLM is not available or compiled" >&2
  echo "$0: Error: We used to install it by default, but." >&2
  echo "$0: Error: this is no longer the case." >&2
  echo "$0: Error: To install it, go to $KALDI_ROOT/tools" >&2
  echo "$0: Error: and run extras/install_irstlm.sh" >&2
  exit 1
fi

cd $dir
# Make directory of links to the WSJ disks such as 11-13.1.  This relies on the command
# line arguments being absolute pathnames.
rm -r links/ 2>/dev/null
mkdir links/
ln -s $* links

# Do some basic checks that we have what we expected.
if [ ! -d links/11-13.1 -o ! -d links/13-34.1 -o ! -d links/11-2.1 ]; then
  echo "wsj_data_prep.sh: Spot check of command line arguments failed"
  echo "Command line arguments must be absolute pathnames to WSJ directories"
  echo "with names like 11-13.1."
  echo "Note: if you have old-style WSJ distribution,"
  echo "local/cstr_wsj_data_prep.sh may work instead, see run.sh for example."
  exit 1;
fi

# This version for SI-84

cat links/11-13.1/wsj0/doc/indices/train/tr_s_wv1.ndx | \
 $local/ndx2flist.pl $* | sort | \
 grep -v -i 11-2.1/wsj0/si_tr_s/401 | sed s/.wv1/.wav/ > train_si84.flist

nl=`cat train_si84.flist | wc -l`
[ "$nl" -eq 7138 ] || echo "Warning: expected 7138 lines in train_si84.flist, got $nl"

# This version for SI-284
cat links/13-34.1/wsj1/doc/indices/si_tr_s.ndx \
 links/11-13.1/wsj0/doc/indices/train/tr_s_wv1.ndx | \
 $local/ndx2flist.pl  $* | sort | \
 grep -v -i 11-2.1/wsj0/si_tr_s/401 | sed s/.wv1/.wav/ > train_si284.flist

nl=`cat train_si284.flist | wc -l`
[ "$nl" -eq 37416 ] || echo "Warning: expected 37416 lines in train_si284.flist, got $nl"

# Finding the transcript files:
for x in $*; do find -L $x -iname '*.dot'; done > dot_files.flist

# Convert the transcripts into our format (no normalization yet)
for x in train_si284; do
   $local/flist2scp.pl $x.flist | sort > ${x}_sph.scp
   cat ${x}_sph.scp | awk '{print $1}' | $local/find_transcripts.pl  dot_files.flist > $x.trans1
done

# Do some basic normalization steps.  At this point we don't remove OOVs--
# that will be done inside the training scripts, as we'd like to make the
# data-preparation stage independent of the specific lexicon used.
noiseword="<NOISE>";
for x in train_si284; do
   cat $x.trans1 | $local/normalize_transcript.pl $noiseword | sort > $x.txt || exit 1;
done

# Create scp's with wav's. (the wv1 in the distribution is not really wav, it is sph.)
for x in train_si284; do
  awk '{printf("%s %s\n", $1, $2);}' < ${x}_sph.scp > ${x}_wav.scp
done

# Make the utt2spk and spk2utt files.
for x in train_si284; do
   cat ${x}_sph.scp | awk '{print $1}' | perl -ane 'chop; m:^...:; print "$_ $&\n";' > $x.utt2spk
   cat $x.utt2spk | $utils/utt2spk_to_spk2utt.pl > $x.spk2utt || exit 1;
done


#in case we want to limit lm's on most frequent words, copy lm training word frequency list
cp links/13-32.1/wsj1/doc/lng_modl/vocab/wfl_64.lst $lmdir
chmod u+w $lmdir/*.lst # had weird permissions on source.

# The 20K vocab, open-vocabulary language model (i.e. the one with UNK), without
# verbalized pronunciations.   This is the most common test setup, I understand.

cp links/13-32.1/wsj1/doc/lng_modl/base_lm/bcb20onp.z $lmdir/lm_bg.arpa.gz || exit 1;
chmod u+w $lmdir/lm_bg.arpa.gz

# trigram would be:
cat links/13-32.1/wsj1/doc/lng_modl/base_lm/tcb20onp.z | \
 perl -e 'while(<>){ if(m/^\\data\\/){ print; last;  } } while(<>){ print; }' | \
 gzip -c -f > $lmdir/lm_tg.arpa.gz || exit 1;

prune-lm --threshold=1e-7 $lmdir/lm_tg.arpa.gz $lmdir/lm_tgpr.arpa || exit 1;
gzip -f $lmdir/lm_tgpr.arpa || exit 1;

# repeat for 5k language models
cp links/13-32.1/wsj1/doc/lng_modl/base_lm/bcb05onp.z  $lmdir/lm_bg_5k.arpa.gz || exit 1;
chmod u+w $lmdir/lm_bg_5k.arpa.gz

# trigram would be: !only closed vocabulary here!
cp links/13-32.1/wsj1/doc/lng_modl/base_lm/tcb05cnp.z $lmdir/lm_tg_5k.arpa.gz || exit 1;
chmod u+w $lmdir/lm_tg_5k.arpa.gz
gunzip $lmdir/lm_tg_5k.arpa.gz
tail -n 4328839 $lmdir/lm_tg_5k.arpa | gzip -c -f > $lmdir/lm_tg_5k.arpa.gz
rm $lmdir/lm_tg_5k.arpa

prune-lm --threshold=1e-7 $lmdir/lm_tg_5k.arpa.gz $lmdir/lm_tgpr_5k.arpa || exit 1;
gzip -f $lmdir/lm_tgpr_5k.arpa || exit 1;


if [ ! -f wsj0-train-spkrinfo.txt ] || [ `cat wsj0-train-spkrinfo.txt | wc -l` -ne 134 ]; then
  rm wsj0-train-spkrinfo.txt
  ! wget https://catalog.ldc.upenn.edu/docs/LDC93S6A/wsj0-train-spkrinfo.txt && \
    echo "Getting wsj0-train-spkrinfo.txt from backup location" && \
    wget --no-check-certificate https://sourceforge.net/projects/kaldi/files/wsj0-train-spkrinfo.txt
fi

if [ ! -f wsj0-train-spkrinfo.txt ]; then
  echo "Could not get the spkrinfo.txt file from LDC website (moved)?"
  echo "This is possibly omitted from the training disks; couldn't find it."
  echo "Everything else may have worked; we just may be missing gender info"
  echo "which is only needed for VTLN-related diagnostics anyway."
  exit 1
fi
# Note: wsj0-train-spkrinfo.txt doesn't seem to be on the disks but the
# LDC put it on the web.  Perhaps it was accidentally omitted from the
# disks.

cat links/11-13.1/wsj0/doc/spkrinfo.txt \
    links/13-32.1/wsj1/doc/evl_spok/spkrinfo.txt \
    links/13-34.1/wsj1/doc/dev_spok/spkrinfo.txt \
    links/13-34.1/wsj1/doc/train/spkrinfo.txt \
   ./wsj0-train-spkrinfo.txt  | \
    perl -ane 'tr/A-Z/a-z/; m/^;/ || print;' | \
   awk '{print $1, $2}' | grep -v -- -- | sort | uniq > spk2gender


echo "Data preparation succeeded"