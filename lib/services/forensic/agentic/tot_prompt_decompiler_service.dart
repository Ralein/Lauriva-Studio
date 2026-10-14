/// Recovered system prompt template or agentic loop metadata.
class DecompiledAgentTrace {
  final String estimatedPersona;
  final int estimatedCritiqueLoops;
  final List<String> detectedSystemDirectives;
  final double agenticConfidence;

  const DecompiledAgentTrace({
    required this.estimatedPersona,
    required this.estimatedCritiqueLoops,
    required this.detectedSystemDirectives,
    required this.agenticConfidence,
  });

  Map<String, dynamic> toJson() => {
        'estimatedPersona': estimatedPersona,
        'estimatedCritiqueLoops': estimatedCritiqueLoops,
        'detectedSystemDirectives': detectedSystemDirectives,
        'agenticConfidence': agenticConfidence,
      };
}

/// Service that de-compiles multi-agent Tree-of-Thought generation pipelines.
class TotPromptDecompilerService {
  /// De-compiles [text] to recover underlying system prompt directives.
  DecompiledAgentTrace decompile(String text) {
    final lower = text.toLowerCase();
    final directives = <String>[];
    String persona = 'General Assistant';
    int loops = 1;
    double confidence = 0.0;

    // 1. Detect Persona Markers
    if (lower.contains('as an expert') || lower.contains('from an academic standpoint') || lower.contains('rigorous scholar')) {
      persona = 'Academic Researcher / Scholar';
      confidence += 0.35;
      directives.add('Adopt an authoritative, academic scholarly persona.');
    } else if (lower.contains('in today\'s fast-paced digital world') || lower.contains('let\'s dive into')) {
      persona = 'SEO Content Marketer';
      confidence += 0.40;
      directives.add('Engage reader with relatable conversational hooks.');
    }

    // 2. Detect Multi-Agent Critique & Polish Loops
    if (lower.contains('to put it another way') || lower.contains('more precisely,') || lower.contains('re-evaluating our previous premise')) {
      loops = 3;
      confidence += 0.30;
      directives.add('Run self-critique loop to eliminate ambiguity.');
    }

    // 3. Detect Chain-of-Thought Triads
    if (lower.contains('first and foremost') && lower.contains('subsequently') && lower.contains('ultimately')) {
      confidence += 0.25;
      directives.add('Structure output into balanced tripartite progressions.');
    }

    return DecompiledAgentTrace(
      estimatedPersona: persona,
      estimatedCritiqueLoops: loops,
      detectedSystemDirectives: directives,
      agenticConfidence: confidence.clamp(0.0, 1.0),
    );
  }
}
