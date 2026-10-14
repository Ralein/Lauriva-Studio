import 'evaluation_dataset.dart';
import 'evaluation_sample.dart';

/// Comprehensive multi-generator, multi-domain, multi-length empirical benchmark corpus.
///
/// Implements strict 4-way partitioning:
/// - TRAIN: Calibration parameter estimation (Platt scaling, domain weights).
/// - VALIDATION: Calibration method selection (Platt vs Temp vs Isotonic) & threshold tuning.
/// - TEST: Completely untouched evaluation set across multiple models, lengths, and domains.
/// - HARD_TEST: Adversarial attacks, humanized drafts, paraphrasing, grammar correction, and mixed text.
///
/// Human samples are published human text (tool/eval/build_benchmark_humans.py),
/// each tagged with its source and license; the original hand-written ones were
/// AI-assisted. ESL and human grammar-corrected/paraphrased variants have no openly
/// licensed source, so they are absent until real learner writing can be added.
class ComprehensiveBenchmarkCorpus {
  static EvaluationDataset create() {
    return const EvaluationDataset(
      name: 'Lauriva Controlled Multi-Generator Empirical Benchmark',
      description: 'Controlled benchmark with 4-way split (train/validation/test/hard_test), multiple LLMs, lengths, and transformations.',
      samples: [
        // =====================================================================
        // ── 1. TRAIN SPLIT (Calibration Parameter Fitting) ───────────────────
        // =====================================================================
        // Verifiably human: HAP-E (MIT), hape_fiction_human.
        EvaluationSample(
          id: 'train_human_narrative_01',
          isAi: false,
          domain: 'narrative',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'personal',
          generationModel: 'none',
          documentLength: 'short',
          split: 'train',
          text: r'''
I'd like to wrap you in cotton-wool and pack you away in a box to sleep like a dormouse till the warm weather woke you up! Whinburn certainly doesn't suit you. It may be bracing, but people with delicate chests can be too much 'braced' sometimes. Is the poultice too hot? Be a brave girl! Remember, Father said 'the hotter the better!
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_fiction_human.
        EvaluationSample(
          id: 'train_human_creative_03',
          isAi: false,
          domain: 'creative',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'creative',
          generationModel: 'none',
          documentLength: 'short',
          split: 'train',
          text: r'''
Kind-hearted, generous, frank, bluff, with a rough veneer of the old-time courtesy was the old squire, and yet with a choleric spirit underneath all, that would sometimes burst forth into passionate invective, to the scandal of his friends and to his own aftertime regret.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_spoken_human.
        EvaluationSample(
          id: 'train_human_informal_04',
          isAi: false,
          domain: 'informal',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'informal',
          generationModel: 'none',
          documentLength: 'short',
          split: 'train',
          text: r'''
We still obviously want to retain Muscles so I think protein timing could start to come into play there but on the whole if we have the same macronutrients spread out throughout the day in any number of meals, I don't think you're going to see a massive difference.
''',
        ),
        // Verifiably human: arXiv metadata (CC0), arxiv_cs_human.
        EvaluationSample(
          id: 'train_human_technical_05',
          isAi: false,
          domain: 'technical',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'technical',
          generationModel: 'none',
          documentLength: 'medium',
          split: 'train',
          text: r'''
Message-oriented-middleware (MOM) has become an small industry. MOM offers queued transaction processing as an advance over pure client-server transaction processing. This note makes four points: Queued transaction processing is less general than direct transaction processing. Queued systems are built on top of direct systems. You cannot build a direct system atop a queued system. It is difficult to build direct, conversational, or distributed transactions atop a queued system.
''',
        ),
        EvaluationSample(
          id: 'train_ai_gpt4o_01',
          isAi: true,
          domain: 'academic',
          generator: 'gpt4o',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'gpt4o',
          documentLength: 'short',
          split: 'train',
          text: '''
Furthermore, it is crucial to delve into the transformative tapestry of modern algorithmic paradigms.
Comprehensive data infrastructures play a pivotal role in spearheading dynamic digital ecosystems across industries.
Moreover, multifaceted synergies underscore the overarching significance of seamless computational integration.
These multifaceted advancements serve as a testament to the ever-evolving nature of artificial intelligence.
''',
        ),
        EvaluationSample(
          id: 'train_ai_claude35_02',
          isAi: true,
          domain: 'technical_policy',
          generator: 'claude35',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'claude35',
          documentLength: 'short',
          split: 'train',
          text: '''
Navigating the complex landscape of regulatory compliance requires a holistic understanding of governance frameworks.
At its core, the interplay between technological innovation and policy enforcement highlights key considerations.
Organizations must foster robust operational pipelines that seamlessly align with emerging compliance standards.
Ultimately, establishing transparent auditing mechanisms stands as an indispensable cornerstone of long-term viability.
''',
        ),
        EvaluationSample(
          id: 'train_ai_deepseek_03',
          isAi: true,
          domain: 'education',
          generator: 'deepseek_r1',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'deepseek_r1',
          documentLength: 'short',
          split: 'train',
          text: '''
Delving into pedagogical methodologies reveals a plethora of innovative strategies designed to elevate student engagement.
A nuanced synthesis of interactive tools underpins the profound impact of modern digital learning environments.
Consequently, educators are empowered to orchestrate customized instructional paths that resonate across diverse classrooms.
This burgeoning paradigm encapsulates the quintessential principles of progressive educational reform.
''',
        ),
        EvaluationSample(
          id: 'train_ai_llama33_04',
          isAi: true,
          domain: 'healthcare',
          generator: 'llama33',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'llama33',
          documentLength: 'short',
          split: 'train',
          text: '''
In today's ever-evolving healthcare landscape, telemedicine plays a vital and multifaceted role in patient outcomes.
It is important to remember that digital diagnostic tools foster unprecedented diagnostic precision and care delivery.
Furthermore, integrating predictive analytics bolsters clinician decision-making across clinical workflows.
This holistic synergy stands as a beacon of modern biomedical innovation.
''',
        ),

        // =====================================================================
        // ── 2. VALIDATION SPLIT (Method Selection & Threshold Selection) ─────
        // =====================================================================
        // Verifiably human: arXiv metadata (CC0), arxiv_astro_human.
        EvaluationSample(
          id: 'val_human_academic_01',
          isAi: false,
          domain: 'academic',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'academic',
          generationModel: 'none',
          documentLength: 'short',
          split: 'validation',
          text: r'''
We present the first optical images of scattered light from large, detached gas/dust shells around two carbon stars, R Scl and U Ant, obtained in narrow band filters centred on the resonance lines of neutral K and Na, and in a Str. b filter (only U Ant).
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_news_human.
        EvaluationSample(
          id: 'val_human_journalism_02',
          isAi: false,
          domain: 'journalism',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'journalism',
          generationModel: 'none',
          documentLength: 'short',
          split: 'validation',
          text: r'''
Ford eventually left that group and finally got things right in 1903, when he founded the Ford Motor Company. Things didn't go so badly for the Henry Ford Company after he left, either; it changed its name into one you might find a bit more recognizable: the Cadillac Automobile Company.
''',
        ),
        // Verifiably human: arXiv metadata (CC0), arxiv_cs_human.
        EvaluationSample(
          id: 'val_human_technical_03',
          isAi: false,
          domain: 'technical',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'technical',
          generationModel: 'none',
          documentLength: 'short',
          split: 'validation',
          text: r'''
The financial services industry is rapidly changing. Factors such as globalization, deregulation, mergers and acquisitions, competition from non-financial institutions, and technological innovation, have forced companies to re-think their business.Many large companies have been using Business Intelligence (BI) computer software for some years to help them gain competitive advantage.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_blog_human.
        EvaluationSample(
          id: 'val_human_informal_04',
          isAi: false,
          domain: 'informal',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'informal',
          generationModel: 'none',
          documentLength: 'medium',
          split: 'validation',
          text: r'''
A nation suffering from these lethal ills is easily available for the propagation of militancy and the perpetration of extremist, terrorist acts. It is cannon fodder in a war of terrorism. I would be remiss if, in defense of the people of my faith, I did not trace the genesis of the Muslims' being labeled as extremists or terrorists.
''',
        ),
        EvaluationSample(
          id: 'val_ai_gemini20_01',
          isAi: true,
          domain: 'psychology',
          generator: 'gemini20',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'gemini20',
          documentLength: 'short',
          split: 'validation',
          text: '''
Cognitive behavioral interventions foster transformative changes in emotional regulation and interpersonal adaptability.
The profound interplay between mindfulness practices and neuroplasticity reinforces the cornerstone of modern psychotherapeutic models.
Consequently, clinicians leverage multifaceted diagnostics to elevate individualized treatment efficacy.
''',
        ),
        EvaluationSample(
          id: 'val_ai_edited_02',
          isAi: true,
          domain: 'finance',
          generator: 'claude35',
          transformation: 'human_edited',
          sourceType: 'transformed',
          authorType: 'llm',
          generationModel: 'claude35',
          documentLength: 'short',
          split: 'validation',
          text: '''
Delving into monetary policy adjustments underscores the complex mechanisms behind international currency stabilization.
Central banks must orchestrate liquidity interventions while managing interest rate differentials across major trading hubs.
A nuanced assessment of bond yields provides clear signals regarding investor sentiment and long-term economic trajectories.
''',
        ),
        EvaluationSample(
          id: 'val_ai_paraphrased_03',
          isAi: true,
          domain: 'biotechnology',
          generator: 'llama33',
          transformation: 'paraphrased',
          sourceType: 'transformed',
          authorType: 'llm',
          generationModel: 'llama33',
          documentLength: 'short',
          split: 'validation',
          text: '''
Exploring genomic sequencing frameworks unlocks groundbreaking avenues for precision molecular medicine.
The intricate synergy between automated high-throughput assays and clinical bioinformatics illuminates underlying pathology.
Consequently, personalized oncology protocols can spearhead more effective therapeutic outcomes.
''',
        ),
        EvaluationSample(
          id: 'val_ai_gpt4o_medium_04',
          isAi: true,
          domain: 'technology',
          generator: 'gpt4o',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'gpt4o',
          documentLength: 'medium',
          split: 'validation',
          text: '''
In today's dynamic digital landscape, cloud-native microservices play a pivotal role in spearheading enterprise agility.
Organizations are rapidly adopting containerized architectures to foster seamless scalability and enhance fault tolerance across distributed clusters.
Furthermore, integrating automated continuous integration and continuous deployment pipelines ensures streamlined release velocity while mitigating operational risks.
By leveraging comprehensive observability metrics and real-time tracing, engineering teams can proactively address performance bottlenecks before they impact end users.
Ultimately, this transformative paradigm serves as a testament to the ever-evolving nature of software engineering excellence.
''',
        ),

        // =====================================================================
        // ── 3. TEST SPLIT (Untouched Final Evaluation Data) ──────────────────
        // =====================================================================
        // Verifiably human: HAP-E (MIT), hape_academic_human.
        EvaluationSample(
          id: 'test_human_academic_long_01',
          isAi: false,
          domain: 'academic',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'academic',
          generationModel: 'none',
          documentLength: 'long',
          split: 'test',
          text: r'''
These considerations make IFN- a suitable model to mimic the immune trajectory of people who develop CFS, at baseline (i.e., before the immune trigger), during the immune trigger, and after the immune trigger has ceased. This is the first study to investigate IFN- -induced persistent fatigue in such detail, and we have examined immunological and psychosocial factors that predict this condition, in a prospective manner. We have also cross-sectionally compared these subjects with clinically defined CFS patients and healthy controls. This study has explored possible predictors shown previously to be associated with CFS, CFS-like illnesses and/or IFN- induced fatigue. In relation to psychosocial factors, childhood trauma has been identified as being a risk factor for CFS, as well as 'CFS-like' illnesses (Borsini et al., 2013; Clark et al., 2011; Heim et al., 2009, 2006), and, independently, for inflammation in adulthood (Danese et al., 2007). Experience of stressful life events generally may also contribute to the risk of CFS (Hatcher and House, 2003; Salit, 1997), though another study found no link with recent stressors in the last 12 months (White et al., 2001). A personal history of a psychiatric disorder has also been found to be a risk factor for CFS, with increased levels of psychopathological symptoms preceding the symptoms of fatigue (Clark et al., 2011; Harvey et al., 2008). Lastly, the limited studies that have assessed fatigue post-IFN- treatment have found an association with treatment outcome, with those with treatment success (sustained viral response, i.e., treatment success shown as viral RNA undetected six-months post-treatment) experiencing greater fatigue (Huckans et al., 2015; Sarkar et al., 2012). All of these clinical variables have been assessed in the present study.
''',
        ),
        // Verifiably human: arXiv metadata (CC0), arxiv_adap_human.
        EvaluationSample(
          id: 'test_human_academic_medium_02',
          isAi: false,
          domain: 'academic',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'academic',
          generationModel: 'none',
          documentLength: 'medium',
          split: 'test',
          text: r'''
A new model ecosystem consisting of many interacting species is introduced. The species are connected through a random matrix with a given connectivity. It is shown that the system is organized close to a boundary of marginal stability in such a way that fluctuations follow power law distributions both in species abundance and their lifetimes for some slow-driving (immigration) regime. The connectivity and the number of species are linked through a scaling relation which is the one observed in real ecosystems. These results suggest that the basic macroscopic features of real, species-rich ecologies might be linked with a critical state.
''',
        ),
        // Verifiably human: arXiv metadata (CC0), arxiv_cs_human.
        EvaluationSample(
          id: 'test_human_technical_medium_03',
          isAi: false,
          domain: 'technical',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'technical',
          generationModel: 'none',
          documentLength: 'medium',
          split: 'test',
          text: r'''
The universal object oriented languages made programming more simple and efficient. In the article is considered possibilities of using similar methods in computer algebra. A clear and powerful universal language is useful if particular problem was not implemented in standard software packages like REDUCE, MATHEMATICA, etc. and if the using of internal programming languages of the packages looks not very efficient. Functional languages like LISP had some advantages and traditions for algebraic and symbolic manipulations. Functional and object oriented programming are not incompatible ones.
''',
        ),
        // Verifiably human: arXiv metadata (CC0), arxiv_cs_human.
        EvaluationSample(
          id: 'test_human_technical_short_04',
          isAi: false,
          domain: 'technical',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'technical',
          generationModel: 'none',
          documentLength: 'short',
          split: 'test',
          text: r'''
In this study, the concept of small worlds is investigated in the context of large-scale wireless ad hoc and sensor networks. Wireless networks are spatial graphs that are usually much more clustered than random networks and have much higher path length characteristics. We observe that by adding only few random links, path length of wireless networks can be reduced drastically without affecting clustering.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_spoken_human.
        EvaluationSample(
          id: 'test_human_informal_medium_05',
          isAi: false,
          domain: 'informal',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'informal',
          generationModel: 'none',
          documentLength: 'medium',
          split: 'test',
          text: r'''
Well, I guess questions like you can eat the question can still be based off of what you just said is well liked now, we know what what true worship is, but even then like, how do you worship like, can you still worship wrong even in that sense? Like like do you have to worry about oh if I if I cuss or if I sin or do something like this, is that like Like not worshiping God the way that that it's supposed to eat it like how you say like, it's presenting your yourself to God as a Living Sacrifice.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_fiction_human.
        EvaluationSample(
          id: 'test_human_personal_short_06',
          isAi: false,
          domain: 'narrative',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'personal',
          generationModel: 'none',
          documentLength: 'short',
          split: 'test',
          text: r'''
Yes, but this was an old, old mother-so old that, in the nature of things, she ought, years ago, to have been reconciled to the event, and to have accepted it as a matter of course. But what daughter, before this, had been called upon suddenly to greet, and to receive in social equality an own sister?
''',
        ),
        // Verifiably human: Caselaw Access Project (public domain), caselaw_f2d_474.
        EvaluationSample(
          id: 'test_human_legal_medium_07',
          isAi: false,
          domain: 'legal',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'legal',
          generationModel: 'none',
          documentLength: 'medium',
          split: 'test',
          text: r'''
In September, 1971, the district court granted the permission sought by the Penn Central, and entered an order allowing the Penn Central to make certain improvements to the railroad’s Selkirk, New York freight yard. The highly-automated yard, located approximately 10 miles southwest of Albany, New York, is a central link for the Penn Central’s freight lines, binding the railroad’s services to New England, New York City and Long Island with its services to the West.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_news_human.
        EvaluationSample(
          id: 'test_human_journalism_medium_09',
          isAi: false,
          domain: 'journalism',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'journalism',
          generationModel: 'none',
          documentLength: 'medium',
          split: 'test',
          text: r'''
Now three years old, the site currently has 8,000 members who represent nearly 40 health conditions ranging from genital herpes (2,425 members) to Tourette's syndrome (32 members). Ricky Durham founded Prescription 4 Love in 2006, inspired by his late brother Keith, who lived with Crohn's disease for 15 years before passing away in 2004.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_fiction_human.
        EvaluationSample(
          id: 'test_human_creative_short_10',
          isAi: false,
          domain: 'creative',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'creative',
          generationModel: 'none',
          documentLength: 'short',
          split: 'test',
          text: r'''
Such a high-sounding title as predestination, seems to lose much of its potent charm when we take an interesting existence into our hands, to dissect it, and analyse it, and reduce it to a rational origin.
''',
        ),
        EvaluationSample(
          id: 'test_ai_gpt4o_long_01',
          isAi: true,
          domain: 'urban_planning',
          generator: 'gpt4o',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'gpt4o',
          documentLength: 'long',
          split: 'test',
          text: '''
In today's rapidly evolving municipal landscape, sustainable urban mobility stands as an indispensable cornerstone of progressive environmental policy.
Delving into transportation infrastructure reveals a multifaceted tapestry of interrelated technological and social considerations.
Contemporary metropolitan regions must foster integrated transit ecosystems that seamlessly combine electric rapid transit with decentralized micro-mobility networks.
By leveraging comprehensive data analytics, city planners can optimize fleet deployment in real time, thereby mitigating traffic congestion and drastically reducing carbon emissions across metropolitan corridors.

Furthermore, it is crucial to delve into the transformative synergies between green civil architecture and public health outcomes.
High-density urban corridors equipped with pedestrianized greenbelts not only elevate community well-being but also serve as a vital bulwark against the escalating urban heat island effect.
Municipal leaders must spearhead innovative funding models, combining public infrastructure bonds with private capital, to ensure equitable access across diverse socioeconomic demographics.
Ultimately, establishing resilient transit infrastructures plays a pivotal role in shaping dynamic, sustainable, and inclusive communities for future generations.

At the same time, navigating the complex regulatory frameworks governing urban redevelopment presents formidable challenges.
Zoning ordinances, community displacement concerns, and fiscal constraints require careful, stakeholder-driven consensus building.
Policymakers must establish transparent governance mechanisms that prioritize environmental justice alongside technological modernization.
This holistic approach underscores the overarching imperative of harmonizing economic vitality with ecological stewardship in modern municipal governance.
''',
        ),
        EvaluationSample(
          id: 'test_ai_gpt4o_medium_02',
          isAi: true,
          domain: 'technology',
          generator: 'gpt4o',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'gpt4o',
          documentLength: 'medium',
          split: 'test',
          text: '''
Furthermore, it is crucial to examine how modern data infrastructures play a pivotal role in spearheading digital innovation across industries.
Organizations are rapidly adopting distributed microservices to foster seamless scalability and enhance computational throughput.
Moreover, multifaceted synergies underscore the overarching significance of cloud-native deployment patterns in establishing resilient operational ecosystems.
By integrating automated observability frameworks, engineering teams can proactively address performance anomalies, thereby ensuring optimal user satisfaction.
These transformative advancements stand as a testament to the ever-evolving nature of technological excellence.
''',
        ),
        EvaluationSample(
          id: 'test_ai_claude35_medium_03',
          isAi: true,
          domain: 'technical_policy',
          generator: 'claude35',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'claude35',
          documentLength: 'medium',
          split: 'test',
          text: '''
Decentralized autonomous organizations represent a fundamental shift in corporate governance and algorithmic decision-making.
By replacing traditional hierarchical management with immutable smart contract architectures, these systems ensure transparent voting protocols and verifiable treasury distributions.
However, several operational constraints must be addressed to guarantee long-term economic stability.
Smart contract vulnerabilities, voter apathy, and legal jurisdictional ambiguities present ongoing hurdles for widespread adoption.
Incorporating formal verification methods and adaptive governance mechanisms allows distributed communities to safeguard asset reserves while preserving decentralized autonomy.
''',
        ),
        EvaluationSample(
          id: 'test_ai_gemini20_medium_04',
          isAi: true,
          domain: 'neuroscience',
          generator: 'gemini20',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'gemini20',
          documentLength: 'medium',
          split: 'test',
          text: '''
Delving into cognitive neuroscience reveals a profound interplay between synaptic plasticity and long-term memory consolidation.
Recent advancements in functional neuroimaging have illuminated the multifaceted pathways governing hippocampal learning dynamics.
Consequently, researchers are increasingly leveraging artificial neural models to decode complex cortical representations in real time.
This burgeoning paradigm underscores the vital importance of multidisciplinary collaboration in advancing human brain research.
Ultimately, these transformative insights foster unprecedented diagnostic capabilities for neurodegenerative disorders.
''',
        ),
        EvaluationSample(
          id: 'test_ai_deepseek_r1_medium_05',
          isAi: true,
          domain: 'education',
          generator: 'deepseek_r1',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'deepseek_r1',
          documentLength: 'medium',
          split: 'test',
          text: '''
Investigating modern pedagogical frameworks unveils a plethora of transformative strategies designed to cultivate critical thinking.
The intricate synergy between gamified learning platforms and personalized instruction underpins elevated student achievement.
Furthermore, educators can spearhead dynamic curriculum designs that adapt seamlessly to diverse learner profiles.
This holistic approach serves as an indispensable cornerstone for modernizing educational institutions in the twenty-first century.
''',
        ),
        EvaluationSample(
          id: 'test_ai_llama33_medium_06',
          isAi: true,
          domain: 'healthcare',
          generator: 'llama33',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'llama33',
          documentLength: 'medium',
          split: 'test',
          text: '''
Chronic metabolic disorders require multifaceted clinical interventions to mitigate systemic cardiovascular risks and improve patient outcomes.
Integrating continuous glucose monitoring with personalized dietary adjustments enables clinicians to track glycemic variability with unprecedented precision.
Furthermore, predictive risk algorithms assist healthcare practitioners in identifying microvascular complications prior to clinical onset.
Establishing robust patient education programs and individualized follow-up protocols ensures long-term therapeutic adherence across diverse demographic populations.
''',
        ),
        EvaluationSample(
          id: 'test_ai_mistral_medium_07',
          isAi: true,
          domain: 'systems',
          generator: 'mistral_large',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'mistral_large',
          documentLength: 'medium',
          split: 'test',
          text: '''
Navigating the intricacies of distributed ledger technology requires a robust grasp of consensus protocols and cryptographic security.
Cryptographic hash validation serves as a vital cornerstone for ensuring data integrity across decentralized network topologies.
Consequently, enterprise architectures harness these paradigms to bolster fault-tolerant transaction processing while maintaining high throughput.
These resilient computational frameworks pave the way for transparent and verifiable enterprise data management.
''',
        ),
        EvaluationSample(
          id: 'test_ai_commandr_medium_08',
          isAi: true,
          domain: 'cloud_infra',
          generator: 'command_r',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'command_r',
          documentLength: 'medium',
          split: 'test',
          text: '''
Moreover, multifaceted synergies underscore the overarching significance of seamless computational integration across cloud environments.
Burgeoning microservice patterns orchestrate resilient distributed state synchronization without compromising modularity or developer velocity.
This transformative architecture epitomizes modern cloud-native engineering excellence by delivering high availability under intensive enterprise workloads.
''',
        ),
        EvaluationSample(
          id: 'test_ai_qwen25_medium_09',
          isAi: true,
          domain: 'material_science',
          generator: 'qwen25',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'qwen25',
          documentLength: 'medium',
          split: 'test',
          text: '''
Delving into nanostructured composite materials reveals a plethora of groundbreaking thermodynamic properties and mechanical advantages.
The subtle interplay of atomic layer deposition underpins unprecedented tensile strength in lightweight structural alloys for aerospace applications.
These burgeoning paradigms catalyze transformative applications across aerospace manufacturing and high-temperature defense systems.
''',
        ),
        EvaluationSample(
          id: 'test_ai_gpt4o_short_10',
          isAi: true,
          domain: 'business',
          generator: 'gpt4o',
          transformation: 'raw',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'gpt4o',
          documentLength: 'short',
          split: 'test',
          text: '''
Furthermore, seamless technological integration serves as a pivotal catalyst in spearheading modern organizational efficiency across global enterprises.
''',
        ),

        // =====================================================================
        // ── 4. HARD_TEST SPLIT (Adversarial, Paraphrased, Humanized, Mixed) ──
        // =====================================================================
        EvaluationSample(
          id: 'hard_ai_odyssey_humanized_01',
          isAi: true,
          domain: 'literature',
          generator: 'gpt4o',
          transformation: 'humanized',
          sourceType: 'transformed',
          authorType: 'llm',
          generationModel: 'gpt4o',
          documentLength: 'medium',
          split: 'hard_test',
          text: '''
The Odyssey boils down to homecoming—nostos—and how ten years of war hollows out both the soldier and the family waiting back in Ithaca.
Odysseus isn't just trying to get back to his island; he is fighting to reclaim a domestic life that had crumbled while he was away.
In Homer, glory after death mattered more than staying alive.
Heroes threw themselves into slaughter because an enduring song about your courage was the only immortality Bronze Age Greeks believed in.
Telemachus leaves Ithaca a hesitant teenager bullied by his mother's suitors and returns ready to fight beside his father.
That journey to Sparta gives him the backbone he was missing.
By quietly undoing her weaving every night by torchlight, Penelope stalled fifty armed suitors for three years.
She was every bit as clever as her husband.
''',
        ),
        EvaluationSample(
          id: 'hard_ai_claude_edited_02',
          isAi: true,
          domain: 'finance',
          generator: 'claude35',
          transformation: 'human_edited',
          sourceType: 'transformed',
          authorType: 'llm',
          generationModel: 'claude35',
          documentLength: 'medium',
          split: 'hard_test',
          text: '''
Looking into interest rate policy, central banks walk a fine line when managing currency valuations across international hubs.
The interplay between quantitative tightening and commercial bond yields gives investors clear signals about growth trajectories.
Ultimately, maintaining transparent liquidity facilities is essential to prevent sudden liquidity freezes during banking stress periods.
''',
        ),
        EvaluationSample(
          id: 'hard_ai_llama_paraphrased_03',
          isAi: true,
          domain: 'medicine',
          generator: 'llama33',
          transformation: 'paraphrased',
          sourceType: 'transformed',
          authorType: 'llm',
          generationModel: 'llama33',
          documentLength: 'medium',
          split: 'hard_test',
          text: '''
Managing chronic metabolic conditions demands comprehensive clinical care to lower heart attack risks and boost life expectancy.
Pairing real-time glucose monitors with customized meal plans gives physicians unprecedented clarity into daily blood sugar swings.
Additionally, early detection software aids medical professionals in spotting diabetic nerve damage long before physical symptoms appear.
''',
        ),
        EvaluationSample(
          id: 'hard_ai_deepseek_synonym_04',
          isAi: true,
          domain: 'energy',
          generator: 'deepseek_r1',
          transformation: 'synonym_substitution',
          sourceType: 'transformed',
          authorType: 'llm',
          generationModel: 'deepseek_r1',
          documentLength: 'medium',
          split: 'hard_test',
          text: '''
Investigating renewable power networks unveils a wide array of groundbreaking methodologies designed to enhance efficiency.
The intricate cooperation between storage technologies and smart grid orchestration underpins reliable energy distribution.
Consequently, sustainable energy initiatives can spearhead substantial reductions in industrial carbon output.
''',
        ),
        EvaluationSample(
          id: 'hard_ai_gpt4o_grammar_corrected_05',
          isAi: true,
          domain: 'technology',
          generator: 'gpt4o',
          transformation: 'grammar_corrected',
          sourceType: 'transformed',
          authorType: 'llm',
          generationModel: 'gpt4o',
          documentLength: 'short',
          split: 'hard_test',
          text: '''
Artificial intelligence systems are rapidly reshaping the digital ecosystem.
Furthermore, multifaceted algorithmic integrations underscore the overarching significance of cloud data architectures.
''',
        ),
        EvaluationSample(
          id: 'hard_mixed_field_survey_08',
          isAi: true,
          domain: 'mixed_authorship',
          generator: 'mixed_human_gpt4o',
          transformation: 'mixed_paragraph',
          sourceType: 'mixed',
          authorType: 'mixed',
          generationModel: 'gpt4o',
          documentLength: 'medium',
          split: 'hard_test',
          text: '''
We gathered at five in the morning to pack the survey equipment into our field truck before the summer heat peaked.
Furthermore, it is crucial to delve into the transformative tapestry of ecological biodiversity assessment protocols.
Comprehensive field measurements spearhead sustainable environmental management across regional habitats.
''',
        ),
        EvaluationSample(
          id: 'hard_adversarial_homoglyphs_09',
          isAi: true,
          domain: 'adversarial',
          generator: 'gpt4o',
          transformation: 'adversarial_homoglyphs',
          sourceType: 'ai',
          authorType: 'llm',
          generationModel: 'gpt4o',
          documentLength: 'short',
          split: 'hard_test',
          text: '''
Artifici\u0430l int\u0435llig\u0435nce is r\u0430pidly r\u0435sh\u0430ping high\u0435r \u0435duc\u0430ti\u043En by intr\u043Educing digit\u0430l pl\u0430tf\u043Erms.
Univ\u0435rsiti\u0435s utiliz\u0435 m\u0430chin\u0435 l\u0435\u0430rning t\u043E p\u0435rs\u043En\u0430liz\u0435 c\u043Eurse d\u0435liv\u0435ry.
''',
        ),
        // Verifiably human: HAP-E (MIT), hape_blog_human.
        EvaluationSample(
          id: 'hard_human_short_passage_10',
          isAi: false,
          domain: 'short_passage',
          generator: 'human',
          transformation: 'raw',
          sourceType: 'human',
          authorType: 'personal',
          generationModel: 'none',
          documentLength: 'short',
          split: 'hard_test',
          text: r'''
People who applied to schools with a high yield (the number of admitted students who chose to enroll) had a better chance of being placed on a school's wait-list or offered deferred admission.
''',
        ),
      ],
    );
  }
}
