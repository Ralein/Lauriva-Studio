import 'dart:convert';
import 'comprehensive_benchmark_corpus.dart';
import 'evaluation_sample.dart';

/// Container for empirical evaluation benchmark datasets with filtering and partitioning.
class EvaluationDataset {
  final String name;
  final String description;
  final List<EvaluationSample> samples;

  const EvaluationDataset({
    required this.name,
    this.description = '',
    required this.samples,
  });

  int get length => samples.length;
  bool get isEmpty => samples.isEmpty;
  bool get isNotEmpty => samples.isNotEmpty;

  List<EvaluationSample> get humanSamples => samples.where((s) => !s.isAi).toList();
  List<EvaluationSample> get aiSamples => samples.where((s) => s.isAi).toList();

  EvaluationDataset filterByDomain(String domain) {
    return EvaluationDataset(
      name: '$name (domain: $domain)',
      description: description,
      samples: samples.where((s) => s.domain.toLowerCase() == domain.toLowerCase()).toList(),
    );
  }

  EvaluationDataset filterByGenerator(String generator) {
    return EvaluationDataset(
      name: '$name (generator: $generator)',
      description: description,
      samples: samples.where((s) => s.generator.toLowerCase() == generator.toLowerCase()).toList(),
    );
  }

  EvaluationDataset filterByTransformation(String transformation) {
    return EvaluationDataset(
      name: '$name (transform: $transformation)',
      description: description,
      samples: samples.where((s) => s.transformation.toLowerCase() == transformation.toLowerCase()).toList(),
    );
  }

  EvaluationDataset filterBySplit(String split) {
    return EvaluationDataset(
      name: '$name (split: $split)',
      description: description,
      samples: samples.where((s) => s.split.toLowerCase() == split.toLowerCase()).toList(),
    );
  }

  EvaluationDataset get trainSplit => filterBySplit('train');
  EvaluationDataset get validationSplit => filterBySplit('validation');
  EvaluationDataset get testSplit => filterBySplit('test');
  EvaluationDataset get hardTestSplit => filterBySplit('hard_test');

  EvaluationDataset filterByDocumentLength(String length) {
    return EvaluationDataset(
      name: '$name (length: $length)',
      description: description,
      samples: samples.where((s) => s.documentLength.toLowerCase() == length.toLowerCase()).toList(),
    );
  }

  EvaluationDataset filterBySourceType(String sourceType) {
    return EvaluationDataset(
      name: '$name (source: $sourceType)',
      description: description,
      samples: samples.where((s) => s.sourceType.toLowerCase() == sourceType.toLowerCase()).toList(),
    );
  }

  /// Partitions dataset for generator holdout validation (train on all except [holdoutGenerator], test on [holdoutGenerator]).
  ({EvaluationDataset train, EvaluationDataset holdout}) splitHoldout(String holdoutGenerator) {
    final holdoutSamples = samples.where((s) => s.generator.toLowerCase() == holdoutGenerator.toLowerCase()).toList();
    final trainSamples = samples.where((s) => s.generator.toLowerCase() != holdoutGenerator.toLowerCase()).toList();

    return (
      train: EvaluationDataset(
        name: '$name (Train without $holdoutGenerator)',
        samples: trainSamples,
      ),
      holdout: EvaluationDataset(
        name: '$name (Holdout: $holdoutGenerator)',
        samples: holdoutSamples,
      ),
    );
  }

  factory EvaluationDataset.fromJsonString(String jsonStr, {String name = 'Loaded Dataset'}) {
    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is List) {
      final sampleList = decoded.map((item) => EvaluationSample.fromJson(item as Map<String, dynamic>)).toList();
      return EvaluationDataset(name: name, samples: sampleList);
    } else if (decoded is Map<String, dynamic>) {
      final samplesList = (decoded['samples'] as List<dynamic>?) ?? [];
      final sampleList = samplesList.map((item) => EvaluationSample.fromJson(item as Map<String, dynamic>)).toList();
      return EvaluationDataset(
        name: decoded['name'] as String? ?? name,
        description: decoded['description'] as String? ?? '',
        samples: sampleList,
      );
    }
    return EvaluationDataset(name: name, samples: const []);
  }

  String toJsonString() {
    return jsonEncode({
      'name': name,
      'description': description,
      'sampleCount': samples.length,
      'samples': samples.map((s) => s.toJson()).toList(),
    });
  }

  /// Generates the expanded multi-generator controlled benchmark corpus with 4-way splits.
  static EvaluationDataset comprehensiveBenchmarkCorpus() => ComprehensiveBenchmarkCorpus.create();

  /// Generates the curated standard benchmark corpus spanning multi-generator, multi-domain, and adversarial transforms.
  static EvaluationDataset curatedStandardCorpus() {
    return const EvaluationDataset(
      name: 'Lauriva 4.0 Multi-Generator Empirical Benchmark Corpus',
      description: 'Curated 23-sample evaluation corpus with multi-generator holdouts, domain variations, and transform attacks.',
      samples: [
        // ── 1. HUMAN SAMPLES ──
        // Published human text only (tool/eval/build_benchmark_humans.py): the
        // original hand-written samples were AI-assisted, so they measured false
        // positives on AI text. No openly licensed ESL learner corpus exists, so
        // there is no ESL human sample until real learner writing can be added.
        // Verifiably human: HAP-E (MIT), hape_academic_human.
        EvaluationSample(
          id: 'human_academic_01',
          isAi: false,
          domain: 'academic',
          generator: 'human',
          transformation: 'raw',
          text: r'''
Firstly, at a physiological level, the release of endogenous opioids (a correlate of high positive affect) could dampen HPA and ANS responses to stress [15,16]. At a cognitive level, positive affect may facilitate creative problem solving or the appraisal of a stressful situation as an opportunity or challenge [17,18].
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_fiction_human.
        EvaluationSample(
          id: 'human_narrative_02',
          isAi: false,
          domain: 'narrative',
          generator: 'human',
          transformation: 'raw',
          text: r'''
Devere, isolated as it was from the main route of travel (the Santa Fe stages still following the more northern trail), heard merely rumors of the prevailing condition through tarrying hunters, and possibly an occasional army courier, yet soon realized the gravity of the situation because of the almost total cessation of travel by way of the Cimarron and the growing insolence of the surrounding Comanches.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_news_human.
        EvaluationSample(
          id: 'human_journalism_04',
          isAi: false,
          domain: 'journalism',
          generator: 'human',
          transformation: 'raw',
          text: r'''
At the end of the day, the political parties will do what they can" for votes, he says. And with what he's seen so far when it comes to immigration reform, Zenteno says if he ever had a chance to vote in the United States, he wouldn't cast a ballot for Democrats or Republicans. Ana, 20: Everything is complicated .
''',
        ),
        // Verifiably human: arXiv metadata (CC0), arxiv_cs_human.
        EvaluationSample(
          id: 'human_technical_05',
          isAi: false,
          domain: 'technical',
          generator: 'human',
          transformation: 'raw',
          text: r'''
There are many classes of mathematical problems which give rise to matrices, where a large number of the elements are zero. In this case it makes sense to have a special matrix type to handle this class of problems where only the non-zero elements of the matrix are stored.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_fiction_human.
        EvaluationSample(
          id: 'human_creative_06',
          isAi: false,
          domain: 'creative',
          generator: 'human',
          transformation: 'raw',
          text: r'''
But presently a kind of long sigh ran through Dept. A and in another moment a perfect babel of sounds arose and swelled upon the air. There was the mooing of cows, the bleating of woolly sheep, the crying of baby dolls, the choo-choo of iron steam cars.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_blog_human.
        EvaluationSample(
          id: 'human_informal_07',
          isAi: false,
          domain: 'informal',
          generator: 'human',
          transformation: 'raw',
          text: r'''
Who would you hate to be locked in a room with? my family. wait, that happens a lot! other people; i don't know. i don't hate many people. 10. Who would you love being locked in a room with? *grin* or a friend or two.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_blog_human.
        EvaluationSample(
          id: 'human_short_08',
          isAi: false,
          domain: 'short_passage',
          generator: 'human',
          transformation: 'raw',
          text: r'''
I'm not the smartest person in the world, but I took that as a sign that I needed to stop.
''',
        ),
        // Verifiably human: Caselaw Access Project (public domain), caselaw_f2d_474.
        EvaluationSample(
          id: 'human_legal_09',
          isAi: false,
          domain: 'legal',
          generator: 'human',
          transformation: 'raw',
          text: r'''
In determining the merits of this contention, we are required to view the evidence in the manner most favorable to the jury’s verdict and uphold that verdict if substantial evidence exists to support it. Glasser v. United States, 315 U.S. 60, 80, 62 S.Ct. 457, 86 L.Ed.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_academic_human.
        EvaluationSample(
          id: 'human_essay_10',
          isAi: false,
          domain: 'academic_human',
          generator: 'human',
          transformation: 'raw',
          text: r'''
In addition, Spath et al. (2016) report that PwPD were less able to copy a rhythmical model during an entrainment task than healthy controls, and Grahn and Brett (2009) found that this speaker group was less able to process rhythmic tone sequences.
''',
        ),

        // ── 2. AI STANDARD SAMPLES (Known Generators) ──
        EvaluationSample(
          id: 'ai_gpt4o_01',
          isAi: true,
          domain: 'academic',
          generator: 'gpt4o',
          transformation: 'raw',
          text: '''
Furthermore, it is crucial to delve into the transformative tapestry of modern algorithmic paradigms.
Comprehensive data infrastructures play a pivotal role in spearheading dynamic digital ecosystems across industries.
Moreover, multifaceted synergies underscore the overarching significance of seamless computational integration.
These multifaceted advancements serve as a testament to the ever-evolving nature of artificial intelligence.
''',
        ),
        EvaluationSample(
          id: 'ai_claude35_02',
          isAi: true,
          domain: 'technical_policy',
          generator: 'claude35',
          transformation: 'raw',
          text: '''
Navigating the complex landscape of regulatory compliance requires a holistic understanding of governance frameworks.
At its core, the interplay between technological innovation and policy enforcement highlights key considerations.
Organizations must foster robust operational pipelines that seamlessly align with emerging compliance standards.
Ultimately, establishing transparent auditing mechanisms stands as an indispensable cornerstone of long-term viability.
''',
        ),
        EvaluationSample(
          id: 'ai_deepseek_03',
          isAi: true,
          domain: 'education',
          generator: 'deepseek_r1',
          transformation: 'raw',
          text: '''
Delving into pedagogical methodologies reveals a plethora of innovative strategies designed to elevate student engagement.
A nuanced synthesis of interactive tools underpins the profound impact of modern digital learning environments.
Consequently, educators are empowered to orchestrate customized instructional paths that resonate across diverse classrooms.
This burgeoning paradigm encapsulates the quintessential principles of progressive educational reform.
''',
        ),
        EvaluationSample(
          id: 'ai_llama33_04',
          isAi: true,
          domain: 'healthcare',
          generator: 'llama33',
          transformation: 'raw',
          text: '''
In today's ever-evolving healthcare landscape, telemedicine plays a vital and multifaceted role in patient outcomes.
It is important to remember that digital diagnostic tools foster unprecedented diagnostic precision and care delivery.
Furthermore, integrating predictive analytics bolsters clinician decision-making across clinical workflows.
This holistic synergy stands as a beacon of modern biomedical innovation.
''',
        ),
        EvaluationSample(
          id: 'ai_gemini20_05',
          isAi: true,
          domain: 'psychology',
          generator: 'gemini20',
          transformation: 'raw',
          text: '''
Cognitive behavioral interventions foster transformative changes in emotional regulation and interpersonal adaptability.
The profound interplay between mindfulness practices and neuroplasticity reinforces the cornerstone of modern psychotherapeutic models.
Consequently, clinicians leverage multifaceted diagnostics to elevate individualized treatment efficacy.
''',
        ),

        // ── 3. UNSEEN GENERATOR HOLDOUTS ──
        EvaluationSample(
          id: 'ai_mistral_06',
          isAi: true,
          domain: 'systems',
          generator: 'mistral_large',
          transformation: 'raw',
          text: '''
Navigating the intricacies of distributed ledger technology requires a robust grasp of consensus protocols.
Cryptographic hash validation serves as a vital cornerstone for ensuring data integrity across decentralized network topologies.
Consequently, enterprise architectures harness these paradigms to bolster fault-tolerant transaction processing.
''',
        ),
        EvaluationSample(
          id: 'ai_commandr_07',
          isAi: true,
          domain: 'cloud_infra',
          generator: 'command_r',
          transformation: 'raw',
          text: '''
Moreover, multifaceted synergies underscore the overarching significance of seamless computational integration across platforms.
Burgeoning microservice patterns orchestrate resilient distributed state synchronization without compromising modularity.
This transformative architecture epitomizes modern cloud-native engineering excellence.
''',
        ),
        EvaluationSample(
          id: 'ai_qwen25_08',
          isAi: true,
          domain: 'material_science',
          generator: 'qwen25',
          transformation: 'raw',
          text: '''
Delving into nanostructured composite materials reveals a plethora of groundbreaking thermodynamic properties.
The subtle interplay of atomic layer deposition underpins unprecedented tensile strength in lightweight structural alloys.
These burgeoning paradigms catalyze transformative applications across aerospace manufacturing.
''',
        ),

        // ── 4. TRANSFORMATION & ADVERSARIAL ATTACKS ──
        EvaluationSample(
          id: 'ai_humanized_09',
          isAi: true,
          domain: 'business',
          generator: 'gpt4o',
          transformation: 'humanized',
          text: '''
Looking at digital commerce today, rapid growth is changing how retail companies interact with everyday shoppers.
Supply chains require constant monitoring because delivery bottlenecks can quickly hurt customer satisfaction.
Companies that adopt adaptive inventory forecasting gain a measurable advantage over slower competitors.
In practice, combining direct customer feedback with automated fulfillment keeps operational costs under control.
''',
        ),
        EvaluationSample(
          id: 'ai_edited_10',
          isAi: true,
          domain: 'finance',
          generator: 'claude35',
          transformation: 'human_edited',
          text: '''
Delving into monetary policy adjustments underscores the complex mechanisms behind international currency stabilization.
Central banks must orchestrate liquidity interventions while managing interest rate differentials across major trading hubs.
A nuanced assessment of bond yields provides clear signals regarding investor sentiment and long-term economic trajectories.
''',
        ),
        EvaluationSample(
          id: 'ai_paraphrased_11',
          isAi: true,
          domain: 'biotechnology',
          generator: 'llama33',
          transformation: 'paraphrased',
          text: '''
Exploring genomic sequencing frameworks unlocks groundbreaking avenues for precision molecular medicine.
The intricate synergy between automated high-throughput assays and clinical bioinformatics illuminates underlying pathology.
Consequently, personalized oncology protocols can spearhead more effective therapeutic outcomes.
''',
        ),
        EvaluationSample(
          id: 'ai_short_12',
          isAi: true,
          domain: 'short_passage',
          generator: 'gpt4o',
          transformation: 'raw_short',
          text: '''
Furthermore, seamless technological integration serves as a pivotal catalyst in spearheading modern organizational efficiency.
''',
        ),
        EvaluationSample(
          id: 'mixed_paragraph_13',
          isAi: true,
          domain: 'mixed_authorship',
          generator: 'mixed_human_gpt4o',
          transformation: 'mixed_paragraph',
          text: '''
We gathered at five in the morning to pack the survey equipment into our field truck before the summer heat peaked.
Furthermore, it is crucial to delve into the transformative tapestry of ecological biodiversity assessment protocols.
Comprehensive field measurements spearhead sustainable environmental management across regional habitats.
''',
        ),
        EvaluationSample(
          id: 'ai_synonym_replace_14',
          isAi: true,
          domain: 'environmental',
          generator: 'deepseek_r1',
          transformation: 'synonym_substitution',
          text: '''
Investigating renewable power networks unveils a wide array of groundbreaking methodologies designed to enhance efficiency.
The intricate cooperation between storage technologies and smart grid orchestration underpins reliable energy distribution.
Consequently, sustainable energy initiatives can spearhead substantial reductions in industrial emissions.
''',
        ),
      ],
    );
  }
}
