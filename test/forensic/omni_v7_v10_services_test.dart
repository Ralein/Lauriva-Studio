import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/services/forensic/bias/esl_neurodivergent_defense_service.dart';
import 'package:lauriva/services/forensic/author/author_profile_service.dart';
import 'package:lauriva/services/forensic/micro_authorship/micro_authorship_heatmap_service.dart';
import 'package:lauriva/services/forensic/biometrics/keystroke_liveness_service.dart';
import 'package:lauriva/services/forensic/citation/citation_fact_graph_sieve.dart';
import 'package:lauriva/services/forensic/neuro_symbolic/logic_fallacy_sieve.dart';
import 'package:lauriva/services/forensic/agentic/tot_prompt_decompiler_service.dart';
import 'package:lauriva/services/forensic/multimodal/multimodal_artifact_forensics_service.dart';
import 'package:lauriva/services/forensic/legal/daubert_evidentiary_compliance_service.dart';
import 'package:lauriva/services/forensic/crypto/merkle_transparency_log_service.dart';
import 'package:lauriva/services/forensic/topology/topological_homology_service.dart';
import 'package:lauriva/services/forensic/omni_forensic_coordinator.dart';

void main() {
  group('Lauriva Omni (v7 - v10) Services Test Suite', () {
    test('EslNeurodivergentDefenseService detects L1 calques and applies offset', () {
      final service = EslNeurodivergentDefenseService();
      const text = 'In morning, we discuss about the research. We have many informations and knowledges.';
      final result = service.analyze(text);

      expect(result.l1TransferProbability, greaterThan(0.0));
      expect(result.calibrationOffset, lessThan(0.0));
      expect(result.disparateImpactRatio, greaterThanOrEqualTo(0.95));
      expect(result.detectedMarkers, isNotEmpty);
    });

    test('AuthorProfileService creates profile and verifies document similarity', () {
      final service = AuthorProfileService();
      final referenceEssays = [
        'This is my unique cadence. I love short sentences. Sometimes I write with sudden punchy pauses. Exactly here.',
        'Another day, another essay. Punchy pauses are my trademark. Exactly here once more.',
      ];

      final profile = service.createProfile(authorId: 'alice', referenceEssays: referenceEssays);
      expect(profile.authorId, equals('alice'));
      expect(profile.samplesRegistered, equals(2));

      final match = service.evaluateDocument(
        authorId: 'alice',
        text: 'Punchy pauses are great. Exactly here we stop.',
      );
      expect(match.similarityScore, greaterThan(0.50));
    });

    test('MicroAuthorshipHeatmapService decomposes clauses and computes QAI', () {
      final service = MicroAuthorshipHeatmapService();
      const text = 'I felt this personal epiphany in my kitchen, but furthermore rigorous evaluation demonstrates high utility.';
      final report = service.analyze(text);

      expect(report.clauses, isNotEmpty);
      expect(report.quantifiedAuthorshipIndex, inInclusiveRange(0.0, 100.0));
      expect(report.humanClauseCount + report.assistedClauseCount + report.machineClauseCount, equals(report.clauses.length));
    });

    test('KeystrokeLivenessService verifies biological typing and generates ZK digest', () {
      final service = KeystrokeLivenessService();
      final keystrokes = <KeystrokeEvent>[];

      // Simulate human typing with variable flight and dwell times
      int time = 1000;
      for (int i = 0; i < 20; i++) {
        final press = time;
        final release = press + (60 + (i % 5) * 10);
        keystrokes.add(KeystrokeEvent(key: 'a', pressTimestampMs: press, releaseTimestampMs: release));
        time = release + (80 + (i % 7) * 20); // natural flight jitter
      }

      final result = service.evaluateKeystrokeStream(keystrokes);
      expect(result.zkSnarkPassportProofHash, startsWith('0x'));
      expect(result.medianDwellTimeMs, greaterThan(0.0));
    });

    test('CitationFactGraphSieve detects ghost DOIs and valid citations', () {
      final service = CitationFactGraphSieve();
      const text = 'According to (Smith et al., 2023), the finding holds. Also see DOI 10.1234/123456 and (Doe, 2049).';
      final report = service.auditCitations(text);

      expect(report.totalCitationsFound, greaterThan(0));
      expect(report.ghostCitations, greaterThan(0)); // 2049 and /123456 should be flagged
      expect(report.flaggedCitations, isNotEmpty);
    });

    test('LogicFallacySieve detects circular reasoning and shallow coherence', () {
      final service = LogicFallacySieve();
      const text = 'Because the theory is true, therefore the theory is true in all observations.';
      final report = service.audit(text);

      expect(report.hasShallowCoherenceAnomaly, isTrue);
      expect(report.anomalies, isNotEmpty);
      expect(report.anomalies.first.fallacyType, equals('circular_reasoning'));
    });

    test('TotPromptDecompilerService reverse engineers persona directives', () {
      final service = TotPromptDecompilerService();
      const text = 'From an academic standpoint, we must re-evaluating our previous premise to put it another way.';
      final trace = service.decompile(text);

      expect(trace.estimatedPersona, contains('Academic'));
      expect(trace.detectedSystemDirectives, isNotEmpty);
    });

    test('MultimodalArtifactForensicsService validates LaTeX braces', () {
      final service = MultimodalArtifactForensicsService();
      const validText = r'Consider the equation $E = mc^2$ and $\sum_{i=1}^n x_i$.';
      final validReport = service.audit(validText);
      expect(validReport.containsLatexMath, isTrue);
      expect(validReport.latexSyntaxValid, isTrue);

      const invalidText = r'Here is an incomplete equation: $\sum_{i=1^n$.';
      final invalidReport = service.audit(invalidText);
      expect(invalidReport.latexSyntaxValid, isFalse);
    });

    test('DaubertEvidentiaryComplianceService issues FRE 702 certificate', () {
      final service = DaubertEvidentiaryComplianceService();
      final cert = service.issueCertificate(rawText: 'Sample legal brief text.', pAi: 0.85);

      expect(cert.certificateId, startsWith('LAURIVA-LEGAL-'));
      expect(cert.pointEstimateAiProbability, equals(0.85));
      expect(cert.lowerConfidenceBound95, lessThan(0.85));
      expect(cert.upperConfidenceBound95, greaterThan(0.85));
      expect(cert.satisfiesFre702Daubert, isTrue);
    });

    test('MerkleTransparencyLogService commits leaves and validates proofs', () {
      final service = MerkleTransparencyLogService();
      final proof = service.commitLeaf('doc_hash_1');

      expect(proof.leafHash, startsWith('0x'));
      expect(proof.rootHash, startsWith('0x'));
      expect(service.verifyProof(proof), isTrue);
    });

    test('TopologicalHomologyService extracts Betti numbers', () {
      final service = TopologicalHomologyService();
      final text = 'Sentence one is long and detailed. '
          'Sentence two introduces a conceptual point with commas, clauses, and elaboration. '
          'Sentence three returns to the core theme. '
          'Sentence four expands with further evidence. '
          'Sentence five synthesizes the overarching thesis.';

      final report = service.analyze(text);
      expect(report.betti0, equals(1));
      expect(report.betti1, greaterThanOrEqualTo(0));
      expect(report.topologicalInterpretation, isNotEmpty);
    });

    test('OmniForensicCoordinator orchestrates all v7-v10 modules in single pass', () {
      final coordinator = OmniForensicCoordinator();
      const text = 'In morning, we discuss about the research. '
          'I felt a personal epiphany in my laboratory. '
          r'According to (Smith et al., 2023), the equation $E = mc^2$ holds true. '
          'Sentence four establishes the methodology and observations. '
          'Sentence five provides the final verified conclusion.';

      final report = coordinator.analyzeOmni(text: text, rawNeuralAiScore: 0.70);

      expect(report.calibratedAiProbability, inInclusiveRange(0.0, 1.0));
      expect(report.eslDefense.disparateImpactRatio, greaterThanOrEqualTo(0.95));
      expect(report.microAuthorship.clauses, isNotEmpty);
      expect(report.citationAudit.totalCitationsFound, greaterThan(0));
      expect(report.daubertCertificate.satisfiesFre702Daubert, isTrue);
      expect(report.merkleProof.rootHash, startsWith('0x'));
      expect(report.topologicalHomology.betti0, equals(1));
      expect(report.executiveProvenanceSummary, contains('Lauriva Omni-Forensics v7-v10'));
    });
  });
}
