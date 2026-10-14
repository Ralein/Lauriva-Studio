import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'compact_corpus_index.dart';
import 'corpus_delivery_service.dart';
import 'inverted_shingle_index.dart';
import 'source_repository.dart';

/// Represents a compiled, indexed source corpus in memory.
class SourceIndex {
  final List<SourceCorpusDocument> documents;
  final InvertedShingleIndex invertedIndex;

  const SourceIndex({
    required this.documents,
    required this.invertedIndex,
  });

  int get documentCount => documents.length;
}

/// Orchestrates asynchronous loading, decompressing, and indexing of the
/// embedded forensic source corpus.
class CorpusLoader {
  static SourceIndex? _cachedIndex;
  static bool _isLoading = false;

  /// Loads and indexes the corpus on first use, caching in memory.
  static Future<SourceIndex> load() async {
    if (_cachedIndex != null) return _cachedIndex!;
    if (_isLoading) {
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (_cachedIndex != null) return _cachedIndex!;
    }

    _isLoading = true;
    try {
      SourceIndex? loaded;
      // 1. Attempt loading binary or compressed asset bundle if available
      try {
        final byteData = await rootBundle.load('assets/source_corpus.bin');
        final bytes = byteData.buffer.asUint8List();
        loaded = _fromCompressedBytes(bytes);
      } catch (_) {
        // Fallback to embedded structured seed corpus
        loaded = _loadEmbeddedBaselineCorpus();
      }

      _cachedIndex = loaded;
      // Warm default SourceRepository singleton with loaded docs
      for (final doc in loaded.documents) {
        SourceRepository.baselineLiterature.addDocument(doc);
      }

      return loaded;
    } finally {
      _isLoading = false;
    }
  }

  /// Non-blocking warmup during app initialization.
  static Future<void> warmup() async {
    try {
      await load();
    } catch (e) {
      debugPrint('[CorpusLoader] Warmup caught non-fatal exception: $e');
    }
    // Offline fingerprint-only corpus: extracted once to a cache file that every isolate can open.
    try {
      // Not bundled: fetch it in the background (Wi-Fi only); scans use the online tier until it lands.
      if (await CompactCorpusIndex.ensureReady() == null) CorpusDeliveryService.ensureInBackground();
    } catch (e) {
      debugPrint('[CorpusLoader] Compact corpus unavailable: $e');
    }
  }

  static SourceIndex _fromCompressedBytes(Uint8List bytes) {
    try {
      Uint8List decompressed = bytes;
      // Check for gzip magic header (0x1F, 0x8B) or zlib header (0x78)
      if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
        decompressed = Uint8List.fromList(gzip.decode(bytes));
      } else if (bytes.length >= 2 && bytes[0] == 0x78) {
        decompressed = Uint8List.fromList(zlib.decode(bytes));
      }

      final jsonStr = utf8.decode(decompressed);
      final list = jsonDecode(jsonStr) as List<dynamic>;
      final docs = <SourceCorpusDocument>[];
      final index = InvertedShingleIndex();

      for (final item in list) {
        final map = item as Map<String, dynamic>;
        final doc = SourceCorpusDocument(
          id: map['id'] as String? ?? '',
          title: map['title'] as String? ?? 'Untitled',
          author: map['author'] as String?,
          url: map['url'] as String?,
          category: SourceCategory.web,
          content: map['content'] as String? ?? '',
        );
        docs.add(doc);
        index.indexDocument(doc.id, doc.fivegramShingles);
      }
      return SourceIndex(documents: docs, invertedIndex: index);
    } catch (_) {
      return _loadEmbeddedBaselineCorpus();
    }
  }

  static SourceIndex _loadEmbeddedBaselineCorpus() {
    final docs = <SourceCorpusDocument>[
      SourceCorpusDocument(
        id: 'wiki_ai_hist',
        title: 'Wikipedia: History of Artificial Intelligence',
        author: 'Wikipedia Contributors',
        url: 'https://en.wikipedia.org/wiki/History_of_artificial_intelligence',
        category: SourceCategory.web,
        content: 'The history of artificial intelligence (AI) began in antiquity, with myths, stories, '
            'and rumors of artificial beings endowed with intelligence or consciousness by master craftsmen. '
            'The seeds of modern AI were planted by classical philosophers who attempted to describe the '
            'process of human thinking as the mechanical manipulation of symbols.',
      ),
      SourceCorpusDocument(
        id: 'arxiv_attention',
        title: 'Attention Is All You Need (Vaswani et al.)',
        author: 'Ashish Vaswani, Noam Shazeer, Niki Parmar',
        url: 'https://arxiv.org/abs/1706.03762',
        category: SourceCategory.academic,
        content: 'The dominant sequence transduction models are based on complex recurrent or convolutional '
            'neural networks that include an encoder and a decoder. The best performing models also connect the '
            'encoder and decoder through an attention mechanism. We propose a new simple network architecture, '
            'the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely.',
      ),
      SourceCorpusDocument(
        id: 'arxiv_bert',
        title: 'BERT: Pre-training of Deep Bidirectional Transformers',
        author: 'Jacob Devlin, Ming-Wei Chang, Kenton Lee, Kristina Toutanova',
        url: 'https://arxiv.org/abs/1810.04805',
        category: SourceCategory.academic,
        content: 'We introduce a new language representation model called BERT, which stands for Bidirectional '
            'Encoder Representations from Transformers. Unlike recent language representation models, BERT is '
            'designed to pre-train deep bidirectional representations from unlabeled text by jointly conditioning '
            'on both left and right context in all layers.',
      ),
      SourceCorpusDocument(
        id: 'turing_1950',
        title: 'Computing Machinery and Intelligence',
        author: 'A. M. Turing',
        url: 'https://doi.org/10.1093/mind/LIX.236.433',
        category: SourceCategory.academic,
        content: 'I propose to consider the question, Can machines think? This should begin with definitions '
            'of the meaning of the terms machine and think. The definitions might be framed so as to reflect '
            'so far as possible the normal use of the words, but this attitude is dangerous. Instead of attempting '
            'such a definition I shall replace the question by another, which is closely related to it and is expressed '
            'in relatively unambiguous words. The new form of the problem can be described in terms of a game which we call the imitation game.',
      ),
      SourceCorpusDocument(
        id: 'shannon_1948',
        title: 'A Mathematical Theory of Communication',
        author: 'C. E. Shannon',
        url: 'https://doi.org/10.1002/j.1538-7305.1948.tb01338.x',
        category: SourceCategory.academic,
        content: 'The fundamental problem of communication is that of reproducing at one point either exactly '
            'or approximately a message selected at another point. Frequently the messages have meaning; that is they '
            'refer to or are correlated according to some system with certain physical or conceptual entities. These semantic '
            'aspects of communication are irrelevant to the engineering problem. The significant aspect is that the actual '
            'message is one selected from a set of possible messages.',
      ),
      SourceCorpusDocument(
        id: 'arxiv_resnet',
        title: 'Deep Residual Learning for Image Recognition',
        author: 'Kaiming He, Xiangyu Zhang, Shaoqing Ren, Jian Sun',
        url: 'https://arxiv.org/abs/1512.03385',
        category: SourceCategory.academic,
        content: 'Deeper neural networks are more difficult to train. We present a residual learning framework '
            'to ease the training of networks that are substantially deeper than those used previously. We explicitly '
            'reformulate the layers as learning residual functions with reference to the layer inputs, instead of '
            'learning unreferenced functions. We provide comprehensive empirical evidence showing that these residual '
            'networks are easier to optimize, and can gain accuracy from considerably increased depth.',
      ),
      SourceCorpusDocument(
        id: 'arxiv_gan',
        title: 'Generative Adversarial Nets',
        author: 'Ian J. Goodfellow, Jean Pouget-Abadie, Mehdi Mirza, Bing Xu, David Warde-Farley, Sherjil Ozair, Aaron Courville, Yoshua Bengio',
        url: 'https://arxiv.org/abs/1406.2661',
        category: SourceCategory.academic,
        content: 'We propose a new framework for estimating generative models via an adversarial process, in which we '
            'simultaneously train two models: a generative model G that captures the data distribution, and a discriminative '
            'model D that estimates the probability that a sample came from the training data rather than G. The training '
            'procedure for G is to maximize the probability of D making a mistake.',
      ),
      SourceCorpusDocument(
        id: 'arxiv_gpt3',
        title: 'Language Models are Few-Shot Learners (GPT-3)',
        author: 'Tom B. Brown, Benjamin Mann, Nick Ryder, Melanie Subbiah, Jared Kaplan, Prafulla Dhariwal, et al.',
        url: 'https://arxiv.org/abs/2005.14165',
        category: SourceCategory.academic,
        content: 'Recent work has demonstrated substantial gains on many NLP tasks and benchmarks by pre-training '
            'on a large corpus of text followed by fine-tuning on a specific task. While typically task-agnostic in '
            'architecture, this method still requires task-specific fine-tuning datasets of thousands or tens of thousands '
            'of examples. By contrast, humans can generally perform a new language task from only a few examples or from '
            'simple instructions. Here we show that scaling up language models greatly improves task-agnostic, few-shot performance.',
      ),
      SourceCorpusDocument(
        id: 'arxiv_lora',
        title: 'LoRA: Low-Rank Adaptation of Large Language Models',
        author: 'Edward J. Hu, Yelong Shen, Phillip Wallis, Zeyuan Allen-Zhu, Yuanzhi Li, Shean Wang, Lu Wang, Weizhu Chen',
        url: 'https://arxiv.org/abs/2106.09685',
        category: SourceCategory.academic,
        content: 'An important paradigm of natural language processing consists of large-scale pre-training on general '
            'domain data and adaptation to particular tasks or domains. As we pre-train larger models, full fine-tuning, '
            'which retrains all model parameters, becomes less feasible. We propose Low-Rank Adaptation, or LoRA, which '
            'freezes the pre-trained model weights and injects trainable rank decomposition matrices into each layer of '
            'the Transformer architecture, greatly reducing the number of trainable parameters for downstream tasks.',
      ),
      SourceCorpusDocument(
        id: 'arxiv_adam',
        title: 'Adam: A Method for Stochastic Optimization',
        author: 'Diederik P. Kingma, Jimmy Ba',
        url: 'https://arxiv.org/abs/1412.6980',
        category: SourceCategory.academic,
        content: 'We introduce Adam, an algorithm for first-order gradient-based optimization of stochastic objective '
            'functions, based on adaptive estimates of lower-order moments. The method is straightforward to implement, is '
            'computationally efficient, has little memory requirements, is invariant to diagonal rescaling of the gradients, '
            'and is well suited for problems that are large in terms of data and parameters.',
      ),
      SourceCorpusDocument(
        id: 'arxiv_llama',
        title: 'LLaMA: Open and Efficient Foundation Language Models',
        author: 'Hugo Touvron, Thibaut Lavril, Gautier Izacard, Xavier Martinet, Marie-Anne Lachaux, Timothée Lacroix, et al.',
        url: 'https://arxiv.org/abs/2302.13971',
        category: SourceCategory.academic,
        content: 'We introduce LLaMA, a collection of foundation language models ranging from 7B to 65B parameters. '
            'We train our models on trillions of tokens, and show that it is possible to train state-of-the-art models '
            'using publicly available datasets exclusively, without resorting to proprietary and inaccessible datasets. '
            'In particular, LLaMA-13B outperforms GPT-3 (175B) on most benchmarks, and LLaMA-65B is competitive with the '
            'best models, Chinchilla-70B and PaLM-540B.',
      ),
      SourceCorpusDocument(
        id: 'arxiv_scaling_laws',
        title: 'Scaling Laws for Neural Language Models',
        author: 'Jared Kaplan, Sam McCandlish, Tom Henighan, Tom B. Brown, Benjamin Chess, Rewon Child, et al.',
        url: 'https://arxiv.org/abs/2001.08361',
        category: SourceCategory.academic,
        content: 'We investigate empirical scaling laws for language model performance on cross-entropy loss. '
            'The loss scales as a power-law with model size, dataset size, and the amount of compute used for training, '
            'with some trends spanning more than seven orders of magnitude. Other architectural hyperparameters such as '
            'network depth vs width have minimal empirical impact within reasonable ranges.',
      ),
      SourceCorpusDocument(
        id: 'academic_boilerplate',
        title: 'Academic Formulaic Boilerplate Index',
        author: 'Standard Academic Corpus',
        url: 'https://lauriva.app/corpus/academic-formulaic',
        category: SourceCategory.academic,
        content: 'In recent years, deep learning has emerged as a promising methodology. Furthermore, it is '
            'important to note that extensive research has demonstrated significant efficacy. Moreover, future '
            'directions warrant comprehensive exploration in order to fully understand the underlying phenomena.',
      ),
    ];

    final index = InvertedShingleIndex();
    for (final doc in docs) {
      index.indexDocument(doc.id, doc.fivegramShingles);
    }

    return SourceIndex(documents: docs, invertedIndex: index);
  }
}
