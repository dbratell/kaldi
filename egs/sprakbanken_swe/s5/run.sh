#!/usr/bin/env bash

. ./cmd.sh ## You'll want to change cmd.sh to something that will work on your system.
           ## This relates to the queue.
. ./path.sh # so python3 is on the path if not on the system (we made a link to utils/).a

decode_jobs=10  # Normally 10
parallel_jobs=10 # Normally 10
stage=5

# This is a shell script, but it's recommended that you run the commands one by
# one by copying and pasting into the shell.


if [ $stage -le 0 ]; then
    # Download the corpus and prepare parallel lists of sound files and text files
    # Divide the corpus into train, dev and test sets
    echo "--- Download the corpus and split it into train, dev, test ---"
    local/sprak_data_prep.sh  || exit 1;
    utils/fix_data_dir.sh data/train || exit 1;
    utils/fix_data_dir.sh data/test || exit 1;


    echo "--- Double checking 0.5 ---"
    utils/validate_data_dir.sh --no-text --no-feats data/test || exit 1;

    # Perform text normalisation, prepare dict folder and LM data transcriptions
    echo "--- Perform text normalisation ---"
    local/copy_dict.sh || exit 1;

    echo "--- Double checking 1 ---"
    utils/validate_data_dir.sh --no-text --no-feats data/test || exit 1;

    utils/prepare_lang.sh data/local/dict "<UNK>" data/local/lang_tmp data/lang || exit 1;

    # Now make MFCC features.
    # mfccdir should be some place with a largish disk where you
    # want to store MFCC features.
    mfccdir=mfcctest

    echo "--- Double checking 2 ---"
    utils/validate_data_dir.sh --no-text --no-feats data/test || exit 1;


    # Extract mfccs
    echo "--- Extract MFCCs ---"
    # p was added to the rspecifier (scp,p:$logdir/wav.JOB.scp) in make_mfcc.sh because some
    # wave files are corrupt
    # Will return a warning message because of the corrupt audio files, but compute them anyway
    # If this step fails and prints a partial diff, rerun from sprak_data_prep.sh

    # steps/make_mfcc.sh --nj 10 --cmd $train_cmd data/test exp/make_mfcc/test test mfcc || exit 1;
    # steps/make_mfcc.sh --nj 10 --cmd $train_cmd data/train exp/make_mfcc/train mfcc || exit 1;

    make_mfcc_jobs=2  # normally 10 but with small datasets, 10 is too much.
    steps/make_mfcc.sh --nj $make_mfcc_jobs --cmd $train_cmd data/test || exit 1;
    steps/make_mfcc.sh --nj $make_mfcc_jobs --cmd $train_cmd data/train || exit 1;

    # Compute cepstral mean and variance normalisation
    echo "--- Compute cepstral mean and variance normalisation ---"
    # steps/compute_cmvn_stats.sh data/test exp/make_mfcc/test mfcc || exit 1;
    # steps/compute_cmvn_stats.sh data/train exp/make_mfcc/train mfcc || exit 1;

    steps/compute_cmvn_stats.sh data/test || exit 1;
    steps/compute_cmvn_stats.sh data/train || exit 1;

    # Repair data set (remove corrupt data points with corrupt audio)

    echo "--- Repair data set ---"

    utils/fix_data_dir.sh data/test || exit 1;
    utils/fix_data_dir.sh data/train || exit 1;

    # Train LM with irstlm
    echo "--- Train LM with irstlm ---"
    # TODO: This is no longer installed by default so script should check if it exists first.
    # To install: To install it, go to ./../../../tools and run extras/install_irstlm.sh
    #creates 3g or 4g dictionary and importantly G.fst
    #local/train_irstlm.sh data/local/transcript_lm/transcripts.uniq 3 "3g" data/lang data/local/train3_lm &> data/local/3g.log &
    local/train_irstlm.sh data/local/transcript_lm/transcripts.uniq 4 "4g" data/lang data/local/train4_lm &> data/local/4g.log || exit 1;

    #speed test only 120 utterances per speaker
    echo "--- Extract 120 utterances per speaker to use for testing ---"
    test_set_size=10  # originally 120
    utils/subset_data_dir.sh --per-spk data/test $test_set_size data/test120_p_spk || exit 1;


    # Train monophone model on short utterances  AFTER THIS ONE CAN SEE THE ALIGNMNT BETWEEN FRAMES AND PHONES USING COMMAND SHOW_ALIGNMENTS
    echo "--- Train monophone model on short utterances ---"
    train_mono_jobs=2 # Normally 10
    steps/train_mono.sh --nj $train_mono_jobs --cmd "$train_cmd" data/train data/lang exp/mono || exit 1;

    # Ensure that LMs are created

    echo "--- Ensure that LMs are created ---"
    utils/mkgraph.sh data/lang_test_4g exp/mono exp/mono/graph_4g || exit 1;

    # Ensure that all graphs are constructed

    echo "--- Ensure that all graphs are created ---"

    steps/decode.sh --config conf/decode_dnn.config --nj $decode_jobs --cmd "$decode_cmd" \
                    exp/mono/graph_4g data/test120_p_spk exp/mono/decode || exit 1;

    # Get alignments from monophone system.
    echo "--- Get alignments from monophone system ---"
    steps/align_si.sh --nj $parallel_jobs --cmd "$train_cmd" \
                      data/train data/lang exp/mono exp/mono_ali || exit 1;

fi

if [ $stage -le 1 ]; then
    # train tri1 [first triphone pass]
    echo "--- train tri1 [first triphone pass] ---"
    # steps/train_deltas.sh --boost-silence 1.25 --cmd "$train_cmd" \
    steps/train_deltas.sh --cmd "$train_cmd" \
      5800 96000 data/train data/lang exp/mono_ali exp/tri1 || exit 1;
fi


if [ $stage -le 2 ]; then
    #make graph
    echo "--- make tr1 graph ---"
    mkdir -p exp/tr1/graph_4g
    utils/mkgraph.sh data/lang_test_4g exp/tri1 exp/tri1/graph_4g || exit 1;
fi

if [ $stage -le 3 ]; then
    steps/decode.sh --config conf/decode_dnn.config --nj $decode_jobs --cmd "$decode_cmd" \
      exp/tri1/graph_4g data/test120_p_spk exp/tri1/decode_test120_p_spk || exit 1;
fi

if [ $stage -le 4 ]; then
    steps/align_si.sh --nj $parallel_jobs --cmd "$train_cmd" \
      data/train data/lang exp/tri1 exp/tri1_ali || exit 1;
    
    
    # Train tri2a, which is deltas + delta-deltas.
    echo "--- Train tri2a, which is deltas + delta-deltas ---"
    steps/train_deltas.sh --cmd "$train_cmd" \
      7500 125000 data/train data/lang exp/tri1_ali exp/tri2a || exit 1;
    
    echo "--- make graph ---"
    utils/mkgraph.sh data/lang_test_4g exp/tri2a exp/tri2a/graph_4g || exit 1;
    
    steps/decode.sh --nj $decode_jobs --cmd "$decode_cmd" \
      exp/tri2a/graph_4g data/test120_p_spk exp/tri2a/decode_test120_p_spk|| exit 1;
    
    
    echo "--- Train lda_mllt ---"
    steps/train_lda_mllt.sh --cmd "$train_cmd" \
       --splice-opts "--left-context=5 --right-context=5" \
       7500 125000 data/train data/lang exp/tri1_ali exp/tri2b || exit 1;
    
    utils/mkgraph.sh data/lang_test_4g exp/tri2b exp/tri2b/graph_4g || exit 1;
    steps/decode.sh --nj $decode_jobs --cmd "$decode_cmd" \
      exp/tri2b/graph_4g data/test120_p_spk exp/tri2b/decode_test120_p_spk || exit 1;
    
    
    steps/align_si.sh  --nj $parallel_jobs --cmd "$train_cmd" \
      --use-graphs true data/train data/lang exp/tri2b exp/tri2b_ali  || exit 1;
    
    
    
    
    # From 2b system, train 3b which is LDA + MLLT + SAT.
    echo "--- From 2b system, train 3b which is LDA + MLLT + SAT ---"
    steps/train_sat.sh --cmd "$train_cmd" \
      7500 125000 data/train data/lang exp/tri2b_ali exp/tri3b || exit 1;
    
    # Trying 4-gram language model
    echo "--- Trying 4-gram language model ---"
    utils/mkgraph.sh data/lang_test_4g exp/tri3b exp/tri3b/graph_4g || exit 1;
    
    steps/decode_fmllr.sh --cmd "$decode_cmd" --nj $decode_jobs \
      exp/tri3b/graph_4g data/test120_p_spk exp/tri3b/decode_test120_p_spk || exit 1;
    
    # This is commented out for now as it's not important for the main recipe.
    ## Train RNN for reranking
    #local/sprak_train_rnnlms.sh data/local/dict data/dev/transcripts.uniq data/local/rnnlms/g_c380_d1k_h100_v130k
    ## Consumes a lot of memory! Do not run in parallel
    #local/sprak_run_rnnlms_tri3b.sh data/lang_test_3g data/local/rnnlms/g_c380_d1k_h100_v130k data/test1k exp/tri3b/decode_3g_test1k
    
    
    # From 3b system
    echo "--- From 3b system ---"
    steps/align_fmllr.sh --nj $parallel_jobs --cmd "$train_cmd" \
      data/train data/lang exp/tri3b exp/tri3b_ali || exit 1;
    
    # From 3b system, train another SAT system (tri4a) with all the si284 data.
    
    echo "--- From 3b system, train another SAT system (tri4a) with all the si284 data ---"
    steps/train_sat.sh  --cmd "$train_cmd" \
      13000 300000 data/train data/lang exp/tri3b_ali exp/tri4a || exit 1;
    
    utils/mkgraph.sh data/lang_test_4g exp/tri4a exp/tri4a/graph_4g || exit 1;
    steps/decode_fmllr.sh --nj $decode_jobs --cmd "$decode_cmd" \
       exp/tri4a/graph_4g data/test120_p_spk exp/tri4a/decode_test120_p_spk || exit 1;
    
    
    
    # alignment used to train nnets
    echo "--- alignment used to train nnets ---"
    steps/align_fmllr.sh --nj $parallel_jobs --cmd "$train_cmd" \
      data/train data/lang exp/tri4a exp/tri4a_ali || exit 1;
    
fi
## Works
echo "--- Works ---"
local/sprak_run_nnet_cpu.sh 4g test120_p_spk || exit 1;



# Getting results [see RESULTS file]
echo "--- Getting results [see RESULTS file] ---"
for x in exp/*/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done
