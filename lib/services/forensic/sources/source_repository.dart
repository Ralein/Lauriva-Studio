import '../../text_forensics_lexicons.dart';
import 'match_tokenizer.dart';
import 'winnowing_engine.dart';

/// Category of source material in the forensic corpus.
enum SourceCategory {
  academic(label: 'Academic & Scientific Literature'),
  web(label: 'Public Web / Wikipedia'),
  literature(label: 'Classic & Public Domain Literature'),
  userCorpus(label: 'User-Provided Corpus');

  final String label;
  const SourceCategory({required this.label});
}

/// A reference document in the source plagiarism corpus.
class SourceCorpusDocument {
  final String id;
  final String title;
  final String? author;
  final String? url;
  final SourceCategory category;
  final String content;
  final List<String> tokens;
  final Set<String> trigramShingles;
  final Set<String> fivegramShingles;
  final Set<String> sevengramShingles;

  /// Character offset in [content] where fetched open-access full text
  /// begins (everything before it is the abstract/snippet the search API
  /// returned). Null when [content] holds no full text.
  final int? fullTextOffset;

  /// Public open-access URL the full text was fetched from (for the report
  /// link). Null when [content] holds no full text.
  final String? oaUrl;

  /// Channel that produced the full text (`arxiv_html`, `europepmc_jats`,
  /// `unpaywall_html`, `wikipedia`, …).
  final String? fullTextSource;

  SourceCorpusDocument({
    required this.id,
    required this.title,
    this.author,
    this.url,
    required this.category,
    required this.content,
    this.fullTextOffset,
    this.oaUrl,
    this.fullTextSource,
  })  : tokens = TextForensicsLexicons.extractWords(content),
        trigramShingles = TextForensicsLexicons.extractNgrams(
          TextForensicsLexicons.extractWords(content),
          3,
        ).toSet(),
        fivegramShingles = TextForensicsLexicons.extractNgrams(
          TextForensicsLexicons.extractWords(content),
          5,
        ).toSet(),
        sevengramShingles = TextForensicsLexicons.extractNgrams(
          TextForensicsLexicons.extractWords(content),
          7,
        ).toSet();

  /// Offset-tracked stemmed tokens used by the seed-and-extend aligner.
  late final List<MatchToken> matchTokens = MatchTokenizer.tokenize(content);

  /// Stanford Winnowing fingerprints guaranteeing detection of runs >= 7 tokens.
  late final List<WinnowingFingerprint> winnowingFingerprints =
      const WinnowingEngine().fingerprintTokens(matchTokens);

  /// Stemmed content-bearing trigrams used for edit-tolerant candidate
  /// retrieval (survives inflection and single-word substitutions that
  /// break exact 5-gram lookup).
  late final Set<String> stemTrigramShingles = MatchTokenizer.contentNgrams(matchTokens, 3);

  /// Source sentences (trimmed, non-trivial) for paraphrase alignment.
  late final List<String> sentences = TextForensicsLexicons.splitSentences(content)
      .where((s) => s.trim().length > 20)
      .toList(growable: false);

  /// Which part of [content] a character offset falls in: `full_text`,
  /// `abstract`, or null when this document carries no full text.
  String? textRegionAt(int offset) {
    final ft = fullTextOffset;
    if (ft == null) return null;
    return offset >= ft ? 'full_text' : 'abstract';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'url': url,
        'category': category.name,
        'content': content,
        if (fullTextOffset != null) 'fullTextOffset': fullTextOffset,
        if (oaUrl != null) 'oaUrl': oaUrl,
        if (fullTextSource != null) 'fullTextSource': fullTextSource,
      };

  factory SourceCorpusDocument.fromJson(Map<String, dynamic> json) => SourceCorpusDocument(
        id: json['id'] as String,
        title: json['title'] as String,
        author: json['author'] as String?,
        url: json['url'] as String?,
        category: SourceCategory.values.firstWhere(
          (c) => c.name == json['category'],
          orElse: () => SourceCategory.academic,
        ),
        content: json['content'] as String,
        fullTextOffset: (json['fullTextOffset'] as num?)?.toInt(),
        oaUrl: json['oaUrl'] as String?,
        fullTextSource: json['fullTextSource'] as String?,
      );
}

/// Reference pointing to a specific source in the index.
class SourceMatchCandidate {
  final String documentId;
  final String title;
  final String? url;
  final int sharedShingleCount;

  const SourceMatchCandidate({
    required this.documentId,
    required this.title,
    this.url,
    required this.sharedShingleCount,
  });
}

/// Indexed in-memory source repository with shingle inverted indexing
/// supporting fast candidate retrieval and corpus expansion.
class SourceRepository {
  static final SourceRepository baselineLiterature = SourceRepository(loadDefaultCorpus: true);

  final Map<String, SourceCorpusDocument> _documents = {};
  final Map<String, Set<String>> _shingleIndex = {}; // 5-gram -> Set of docIds
  final Map<String, Set<String>> _stemTrigramIndex = {}; // stemmed 3-gram -> Set of docIds
  final Map<int, Set<String>> _winnowingIndex = {}; // winnowing fingerprint hash -> Set of docIds

  SourceRepository({bool loadDefaultCorpus = true}) {
    if (loadDefaultCorpus) {
      _loadBaselineCorpus();
    }
  }

  /// Adds a source document to the repository and updates inverted shingle index.
  void addDocument(SourceCorpusDocument doc) {
    _documents[doc.id] = doc;
    for (final shingle in doc.fivegramShingles) {
      _shingleIndex.putIfAbsent(shingle, () => {}).add(doc.id);
    }
    for (final shingle in doc.stemTrigramShingles) {
      _stemTrigramIndex.putIfAbsent(shingle, () => {}).add(doc.id);
    }
    for (final fp in doc.winnowingFingerprints) {
      _winnowingIndex.putIfAbsent(fp.hash, () => {}).add(doc.id);
    }
  }

  /// Fast MOSS-standard Winnowing candidate retrieval.
  List<SourceMatchCandidate> findCandidatesByWinnowing(
    List<WinnowingFingerprint> queryFingerprints, {
    int minShared = 1,
  }) {
    final candidateCounts = <String, int>{};
    for (final fp in queryFingerprints) {
      final docIds = _winnowingIndex[fp.hash];
      if (docIds != null) {
        for (final id in docIds) {
          candidateCounts[id] = (candidateCounts[id] ?? 0) + 1;
        }
      }
    }
    final candidates = <SourceMatchCandidate>[];
    candidateCounts.forEach((docId, count) {
      if (count >= minShared) {
        final doc = _documents[docId];
        if (doc != null) {
          candidates.add(
            SourceMatchCandidate(
              documentId: docId,
              title: doc.title,
              url: doc.url,
              sharedShingleCount: count,
            ),
          );
        }
      }
    });
    candidates.sort((a, b) => b.sharedShingleCount.compareTo(a.sharedShingleCount));
    return candidates;
  }

  /// Edit-tolerant candidate lookup over stemmed content trigrams. A copied
  /// passage with a word swapped every few tokens shares few exact 5-grams
  /// but still shares many stemmed trigrams.
  List<SourceMatchCandidate> findCandidatesByStemTrigrams(Set<String> queryTrigrams, {int minShared = 2}) {
    return _rankCandidates(_stemTrigramIndex, queryTrigrams, minShared);
  }

  /// Retrieves document by id.
  SourceCorpusDocument? getDocument(String id) => _documents[id];

  /// All indexed documents.
  Iterable<SourceCorpusDocument> get documents => _documents.values;

  /// Total indexed documents.
  int get documentCount => _documents.length;

  /// Fast inverted index candidate lookup for query 5-gram shingles.
  List<SourceMatchCandidate> findCandidates(Set<String> queryShingles, {int minShared = 2}) {
    return _rankCandidates(_shingleIndex, queryShingles, minShared);
  }

  List<SourceMatchCandidate> _rankCandidates(
    Map<String, Set<String>> index,
    Set<String> queryShingles,
    int minShared,
  ) {
    final candidateCounts = <String, int>{};

    for (final shingle in queryShingles) {
      final docIds = index[shingle];
      if (docIds != null) {
        for (final id in docIds) {
          candidateCounts[id] = (candidateCounts[id] ?? 0) + 1;
        }
      }
    }

    final candidates = <SourceMatchCandidate>[];
    candidateCounts.forEach((docId, count) {
      if (count >= minShared) {
        final doc = _documents[docId];
        if (doc != null) {
          candidates.add(
            SourceMatchCandidate(
              documentId: docId,
              title: doc.title,
              url: doc.url,
              sharedShingleCount: count,
            ),
          );
        }
      }
    });

    candidates.sort((a, b) => b.sharedShingleCount.compareTo(a.sharedShingleCount));
    return candidates;
  }

  /// Seed baseline corpus with seminal references for offline forensic matching.
  void _loadBaselineCorpus() {
    addDocument(
      SourceCorpusDocument(
        id: 'wiki_turing_test',
        title: 'Computing Machinery and Intelligence (A.M. Turing, 1950)',
        author: 'Alan Turing',
        url: 'https://doi.org/10.1093/mind/LIX.236.433',
        category: SourceCategory.academic,
        content: '''
I propose to consider the question, "Can machines think?" This should begin with definitions of the meaning of the terms "machine" and "think".
The new form of the problem can be described in terms of a game which we call the 'imitation game'.
It is played with three people, a man (A), a woman (B), and an interrogator (C) who may be of either sex.
The interrogator stays in a room apart from the other two. The object of the game for the interrogator is to determine which of the other two is the man and which is the woman.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_attention_paper',
        title: 'Attention Is All You Need (Vaswani et al., 2017)',
        author: 'Ashish Vaswani et al.',
        url: 'https://arxiv.org/abs/1706.03762',
        category: SourceCategory.academic,
        content: '''
The dominant sequence transduction models are based on complex recurrent or convolutional neural networks that include an encoder and a decoder.
The best performing models also connect the encoder and decoder through an attention mechanism.
We propose a new simple network architecture, the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely.
Experiments on two machine translation tasks show these models to be superior in quality while being more parallelizable and requiring significantly less time to train.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'declaration_human_rights',
        title: 'Universal Declaration of Human Rights (UN, 1948)',
        author: 'United Nations General Assembly',
        url: 'https://www.un.org/en/about-us/universal-declaration-of-human-rights',
        category: SourceCategory.literature,
        content: '''
All human beings are born free and equal in dignity and rights.
They are endowed with reason and conscience and should act towards one another in a spirit of brotherhood.
Everyone is entitled to all the rights and freedoms set forth in this Declaration, without distinction of any kind, such as race, colour, sex, language, religion, political or other opinion, national or social origin, property, birth or other status.
No one shall be held in slavery or servitude; slavery and the slave trade shall be prohibited in all their forms.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_resnet_paper',
        title: 'Deep Residual Learning for Image Recognition (He et al., 2016)',
        author: 'Kaiming He, Xiangyu Zhang, Shaoqing Ren, Jian Sun',
        url: 'https://arxiv.org/abs/1512.03385',
        category: SourceCategory.academic,
        content: '''
Deeper neural networks are more difficult to train. We present a residual learning framework to ease the training of networks that are substantially deeper than those used previously.
We explicitly reformulate the layers as learning residual functions with reference to the layer inputs, instead of learning unreferenced functions.
We provide comprehensive empirical evidence showing that these residual networks are easier to optimize, and can gain accuracy from considerably increased depth.
On the ImageNet dataset we evaluate residual nets with a depth of up to 152 layers—8 times deeper than VGG nets but still having lower complexity.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_shannon_information',
        title: 'A Mathematical Theory of Communication (C.E. Shannon, 1948)',
        author: 'Claude E. Shannon',
        url: 'https://doi.org/10.1002/j.1538-7305.1948.tb01338.x',
        category: SourceCategory.academic,
        content: '''
The fundamental problem of communication is that of reproducing at one point either exactly or approximately a message selected at another point.
Frequently the messages have meaning; that is they refer to or are correlated according to some system with certain physical or conceptual entities.
These semantic aspects of communication are irrelevant to the engineering problem.
The significant aspect is that the actual message is one selected from a set of possible messages.
The system must be designed to operate for each possible selection, not just the one which will actually be chosen since this is unknown at the time of design.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'literature_orwell_politics',
        title: 'Politics and the English Language (George Orwell, 1946)',
        author: 'George Orwell',
        url: 'https://www.orwellfoundation.com/the-orwell-foundation/orwell/essays-and-other-works/politics-and-the-english-language/',
        category: SourceCategory.literature,
        content: '''
Most people who bother with the matter at all would admit that the English language is in a bad way, but it is generally assumed that we cannot by conscious action do anything about it.
Our civilization is decadent and our language—so the argument runs—must inevitably share in the general collapse.
It follows that any struggle against the abuse of language is a sentimental archaism, like preferring candles to electric light or hansom cabs to aeroplanes.
Underneath this lies the half-conscious belief that language is a natural growth and not an instrument which we shape for our own purposes.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'literature_gettysburg_address',
        title: 'The Gettysburg Address (Abraham Lincoln, 1863)',
        author: 'Abraham Lincoln',
        url: 'https://www.loc.gov/resource/mal.4270600/',
        category: SourceCategory.literature,
        content: '''
Four score and seven years ago our fathers brought forth on this continent, a new nation, conceived in Liberty, and dedicated to the proposition that all men are created equal.
Now we are engaged in a great civil war, testing whether that nation, or any nation so conceived and so dedicated, can long endure.
We are met on a great battle-field of that war. We have come to dedicate a portion of that field, as a final resting place for those who here gave their lives that that nation might live.
It is altogether fitting and proper that we should do this.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'wiki_artificial_intelligence',
        title: 'Artificial Intelligence Overview (Wikipedia)',
        author: 'Wikipedia Contributors',
        url: 'https://en.wikipedia.org/wiki/Artificial_intelligence',
        category: SourceCategory.web,
        content: '''
Artificial intelligence is the intelligence of machines or software, as opposed to the intelligence of living beings, primarily of humans.
It is a field of study in computer science that develops and studies intelligent machines.
Such machines may be called AIs. AI technology is widely used throughout industry, government, and science.
Some high-profile applications include advanced web search engines, recommendation systems, understanding human speech, autonomous vehicles, and generative or creative tools.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'wiki_photosynthesis',
        title: 'Photosynthesis (Wikipedia)',
        author: 'Wikipedia Contributors',
        url: 'https://en.wikipedia.org/wiki/Photosynthesis',
        category: SourceCategory.web,
        content: '''
Photosynthesis is a biological process used by plants, algae, and certain bacteria to convert light energy into chemical energy.
This chemical energy is stored in carbohydrate molecules, such as sugars and starches, which are synthesized from carbon dioxide and water.
In most cases, oxygen is released as a waste product. Most plants, algae, and cyanobacteria perform photosynthesis; such organisms are called photoautotrophs.
Photosynthesis is largely responsible for producing and maintaining the oxygen content of the Earth atmosphere.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'wiki_quantum_computing',
        title: 'Quantum Computing Fundamentals (Wikipedia)',
        author: 'Wikipedia Contributors',
        url: 'https://en.wikipedia.org/wiki/Quantum_computing',
        category: SourceCategory.web,
        content: '''
Quantum computing is a rapidly-emerging technology that harnesses the laws of quantum mechanics to solve problems too complex for classical computers.
Classical computers encode information into binary bits that can either be 0s or 1s.
Quantum computers, on the other hand, utilize quantum bits or qubits, which can exist in multidimensional states of superposition.
Through quantum entanglement and quantum interference, quantum algorithms can process massive combinatorial calculations exponentially faster than classical supercomputers.
''',
      ),
    );

  addDocument(
      SourceCorpusDocument(
        id: 'essay_technology_society',
        title: 'The Impact of Modern Technology on Society (Academic Essay Standard)',
        author: 'Undergraduate Academic Repository',
        category: SourceCategory.academic,
        content: '''
Technology has transformed society in unprecedented ways over the past several decades.
From the advent of personal computing to the rapid expansion of global high-speed telecommunications networks, virtually every aspect of human life has been altered.
While these advancements have dramatically improved communication efficiency, economic productivity, and access to medical information, they have also raised serious questions concerning data privacy, mental health, and social isolation.
As modern society continues to innovate, individuals and governing institutions must collaborate to ensure ethical development.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_climate_change_ipcc',
        title: 'Climate Change 2021: The Physical Science Basis (IPCC Working Group I)',
        author: 'Intergovernmental Panel on Climate Change',
        url: 'https://www.ipcc.ch/report/ar6/wg1/',
        category: SourceCategory.academic,
        content: '''
It is unequivocal that human influence has warmed the atmosphere, ocean and land.
Widespread and rapid changes in the atmosphere, ocean, cryosphere and biosphere have occurred.
The scale of recent changes across the climate system as a whole and the present state of many aspects of the climate system are unprecedented over many centuries to many thousands of years.
Global surface temperature has increased faster since 1970 than in any other 50-year period over at least the last 2000 years.
Human-induced climate change is already affecting many weather and climate extremes in every region across the globe.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_dna_structure_watson_crick',
        title: 'Molecular Structure of Nucleic Acids: A Structure for Deoxyribose Nucleic Acid (Watson & Crick, 1953)',
        author: 'J.D. Watson and F.H.C. Crick',
        url: 'https://doi.org/10.1038/171737a0',
        category: SourceCategory.academic,
        content: '''
We wish to suggest a structure for the salt of deoxyribose nucleic acid.
This structure has novel features which are of considerable biological interest.
The novel feature of the structure is the manner in which the two chains are held together by the purine and pyrimidine bases.
The planes of the bases are perpendicular to the fibre axis. They are joined together in pairs, a single base from one chain being hydrogen-bonded to a single base from the other chain.
It has not escaped our notice that the specific pairing we have postulated immediately suggests a possible copying mechanism for the genetic material.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'literature_wealth_of_nations',
        title: 'An Inquiry into the Nature and Causes of the Wealth of Nations (Adam Smith, 1776)',
        author: 'Adam Smith',
        url: 'https://www.gutenberg.org/ebooks/3300',
        category: SourceCategory.literature,
        content: '''
It is not from the benevolence of the butcher, the brewer, or the baker that we expect our dinner, but from their regard to their own interest.
We address ourselves, not to their humanity but to their self-love, and never talk to them of our own necessities but of their advantages.
Every individual neither intends to promote the public interest, nor knows how much he is promoting it.
He intends only his own security; and by directing that industry in such a manner as its produce may be of the greatest value, he intends only his own gain.
He is in this, as in many other cases, led by an invisible hand to promote an end which was no part of his intention.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_bitcoin_nakamoto',
        title: 'Bitcoin: A Peer-to-Peer Electronic Cash System (Satoshi Nakamoto, 2008)',
        author: 'Satoshi Nakamoto',
        url: 'https://bitcoin.org/bitcoin.pdf',
        category: SourceCategory.academic,
        content: '''
A purely peer-to-peer version of electronic cash would allow online payments to be sent directly from one party to another without going through a financial institution.
Digital signatures provide part of the solution, but the main benefits are lost if a trusted third party is still required to prevent double-spending.
We propose a solution to the double-spending problem using a peer-to-peer distributed timestamp server to generate computational proof of the chronological order of transactions.
The network timestamps transactions by hashing them into an ongoing chain of hash-based proof-of-work, forming a record that cannot be changed without redoing the proof-of-work.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_cryptography_diffie_hellman',
        title: 'New Directions in Cryptography (Diffie & Hellman, 1976)',
        author: 'Whitfield Diffie and Martin E. Hellman',
        url: 'https://doi.org/10.1109/TIT.1976.1055638',
        category: SourceCategory.academic,
        content: '''
We stand today on the brink of a revolution in cryptography.
The development of cheap digital hardware has brought cryptography from the province of governmental agencies and international diplomacy into the commercial realm.
In this paper we propose that it is possible to build public key cryptosystems that allow two parties to communicate securely over an insecure channel without any prior exchange of a secret key.
Such systems rely on trapdoor one-way functions which are easy to compute in one direction but computationally infeasible to invert without special knowledge.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_millers_law',
        title: 'The Magical Number Seven, Plus or Minus Two (Miller, 1956)',
        author: 'George A. Miller',
        url: 'https://doi.org/10.1037/h0043158',
        category: SourceCategory.academic,
        content: '''
My problem is that I have been persecuted by an integer.
For seven years this number has followed me around, has intruded in my most private data, and has assaulted me from the pages of our most public journals.
There is a clear and finite limit to the accuracy with which humans can identify absolute magnitude of unidimensional stimulus attributes.
This span of absolute judgment and the span of immediate memory impose severe limitations on the amount of information that human observers are able to process and retain.
By organizing the stimulus input simultaneously into several dimensions and successively into a sequence of chunks, we manage to break through this informational bottleneck.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_crispr_cas9_doudna',
        title: 'A Programmable Dual-RNA-Guided DNA Endonuclease in Adaptive Bacterial Immunity (Jinek, Doudna, Charpentier et al., 2012)',
        author: 'Jennifer A. Doudna, Emmanuelle Charpentier et al.',
        url: 'https://doi.org/10.1126/science.1225829',
        category: SourceCategory.academic,
        content: '''
Clustered regularly interspaced short palindromic repeats CRISPR and CRISPR-associated Cas systems provide adaptive immunity against viruses and plasmids in bacteria and archaea.
We show here that the Cas9 endonuclease is guided by dual-RNA molecules to cleave double-stranded DNA site-specifically.
The target site sequence must be complementary to the crRNA guide and also contain a short protospacer adjacent motif PAM directly downstream.
Furthermore, we show that this dual-RNA design can be engineered as a single-guide RNA chimera, offering considerable potential for programmable and precise genome editing in cellular systems.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'literature_hamlet_soliloquy',
        title: 'Hamlet: To Be or Not to Be Soliloquy (William Shakespeare, 1603)',
        author: 'William Shakespeare',
        url: 'https://www.folger.edu/explore/shakespeares-works/hamlet/',
        category: SourceCategory.literature,
        content: '''
To be, or not to be, that is the question:
Whether 'tis nobler in the mind to suffer
The slings and arrows of outrageous fortune,
Or to take arms against a sea of troubles
And by opposing end them. To die—to sleep,
No more; and by a sleep to say we end
The heart-ache and the thousand natural shocks
That flesh is heir to: 'tis a consummation
Devoutly to be wish'd.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_einstein_relativity',
        title: 'On the Electrodynamics of Moving Bodies (Albert Einstein, 1905)',
        author: 'Albert Einstein',
        url: 'https://doi.org/10.1002/andp.19053221004',
        category: SourceCategory.academic,
        content: '''
Examples of this sort, together with the unsuccessful attempts to discover any motion of the earth relatively to the light medium, suggest that the phenomena of electrodynamics as well as of mechanics possess no properties corresponding to the idea of absolute rest.
They suggest rather that the same laws of electrodynamics and optics will be valid for all frames of reference for which the equations of mechanics hold good.
We will raise this conjecture to the status of a postulate, and also introduce another postulate, which is only apparently irreconcilable with the former, namely, that light is always propagated in empty space with a definite velocity c which is independent of the state of motion of the emitting body.
These two postulates suffice for the attainment of a simple and consistent theory of the electrodynamics of moving bodies based on Maxwell's theory for stationary bodies.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_bert_devlin',
        title: 'BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding (Devlin et al., 2018)',
        author: 'Jacob Devlin, Ming-Wei Chang, Kenton Lee, Kristina Toutanova',
        url: 'https://arxiv.org/abs/1810.04805',
        category: SourceCategory.academic,
        content: '''
We introduce a new language representation model called BERT, which stands for Bidirectional Encoder Representations from Transformers.
Unlike recent language representation models, BERT is designed to pre-train deep bidirectional representations from unlabeled text by jointly conditioning on both left and right context in all layers.
As a result, the pre-trained BERT model can be fine-tuned with just one additional output layer to create state-of-the-art models for a wide range of tasks, such as question answering and language inference, without substantial task-specific architecture modifications.
BERT is conceptually simple and empirically powerful, obtaining new state-of-the-art results on eleven natural language processing tasks.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_mapreduce_dean',
        title: 'MapReduce: Simplified Data Processing on Large Clusters (Dean & Ghemawat, 2004)',
        author: 'Jeffrey Dean and Sanjay Ghemawat',
        url: 'https://doi.org/10.1145/1327452.1327492',
        category: SourceCategory.academic,
        content: '''
MapReduce is a programming model and an associated implementation for processing and generating large data sets.
Users specify a map function that processes a key/value pair to generate a set of intermediate key/value pairs, and a reduce function that merges all intermediate values associated with the same intermediate key.
Many real world tasks are expressible in this model, as shown in the paper.
Programs written in this functional style are automatically parallelized and executed on a large cluster of commodity machines.
The run-time system takes care of the details of partitioning the input data, scheduling the program execution across a set of machines, handling machine failures, and managing the required inter-machine communication.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'academic_darwin_species',
        title: 'On the Origin of Species by Means of Natural Selection (Charles Darwin, 1859)',
        author: 'Charles Darwin',
        url: 'https://www.gutenberg.org/ebooks/1228',
        category: SourceCategory.literature,
        content: '''
When on board H.M.S. Beagle, as naturalist, I was much struck with certain facts in the distribution of the organic beings inhabiting South America, and in the geological relations of the present to the past inhabitants of that continent.
These facts seemed to throw some light on the origin of species—that mystery of mysteries, as it has been called by one of our greatest philosophers.
As many more individuals of each species are born than can possibly survive, and as, consequently, there is a frequently recurring struggle for existence, it follows that any being, if it vary however slightly in any manner profitable to itself, will have a better chance of surviving, and thus be naturally selected.
From the strong principle of inheritance, any selected variety will tend to propagate its new and modified form.
''',
      ),
    );

    addDocument(
      SourceCorpusDocument(
        id: 'literature_pride_and_prejudice',
        title: 'Pride and Prejudice (Jane Austen, 1813)',
        author: 'Jane Austen',
        url: 'https://www.gutenberg.org/ebooks/1342',
        category: SourceCategory.literature,
        content: '''
It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.
However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered the rightful property of some one or other of their daughters.
"My dear Mr. Bennet," said his lady to him one day, "have you heard that Netherfield Park is let at last?"
Mr. Bennet replied that he had not.
''',
      ),
    );
  }
}
