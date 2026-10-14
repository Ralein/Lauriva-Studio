/// Writing tone profile for the Lauriva Surgical Humanizer.
///
/// Different tones require different rewriting strategies.
/// The prompt template and aggressiveness scale with tone selection.
enum HumanizerTone {
  academic(
    label: 'Academic',
    description: 'Scholarly, formal register with appropriate citation-style structures.',
    icon: '🎓',
    promptHint: 'Use academic register with measured vocabulary, complex syntax, and appropriate hedging language.',
  ),
  casual(
    label: 'Casual',
    description: 'Relaxed, conversational tone with natural speech patterns.',
    icon: '💬',
    promptHint: 'Use conversational language with contractions, colloquialisms, and natural speech rhythms.',
  ),
  professional(
    label: 'Professional',
    description: 'Clear, authoritative business writing with direct expression.',
    icon: '💼',
    promptHint: 'Use professional but accessible language with clear, direct sentences and active voice.',
  ),
  creative(
    label: 'Creative',
    description: 'Expressive, narrative writing with vivid imagery and varied rhythm.',
    icon: '🎨',
    promptHint: 'Use vivid imagery, narrative techniques, irregular sentence rhythms, and expressive vocabulary.',
  ),
  journalistic(
    label: 'Journalistic',
    description: 'News-style writing with inverted pyramid structure and attribution.',
    icon: '📰',
    promptHint: 'Use inverted pyramid structure, direct quotes, factual attribution, and news-style conciseness.',
  );

  final String label;
  final String description;
  final String icon;
  final String promptHint;

  const HumanizerTone({
    required this.label,
    required this.description,
    required this.icon,
    required this.promptHint,
  });
}
