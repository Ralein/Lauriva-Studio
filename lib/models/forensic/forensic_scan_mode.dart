/// Available scan depths for the Forensic Intelligence Engine.
enum ForensicScanMode {
  forensic(
    label: 'Forensic',
    badge: 'FORENSIC',
    description: 'Instant on-device AI authorship, neural stylometry, and token predictability.',
  ),
  fullForensic(
    label: 'Full Forensic',
    badge: 'FULL',
    description: 'Master decoupled audit across AI authorship, source plagiarism, and evidence fusion.',
  ),
  sourceScan(
    label: 'Source Scan',
    badge: 'SOURCES',
    description: 'Dedicated internet & academic literature search and verbatim shingle matches.',
  );

  final String label;
  final String badge;
  final String description;

  const ForensicScanMode({
    required this.label,
    required this.badge,
    required this.description,
  });

  static ForensicScanMode fromName(String? name) {
    if (name == 'sourceScan') return ForensicScanMode.sourceScan;
    if (name == 'forensic') return ForensicScanMode.forensic;
    return ForensicScanMode.fullForensic;
  }
}

/// Sensitivity calibration presets for the Forensic Intelligence Engine.
enum ForensicSensitivity {
  balanced(
    label: 'Balanced',
    badge: 'BALANCED',
    description: 'Optimal calibration for general essays, articles, and mixed writing.',
  ),
  strict(
    label: 'Academic Strict',
    badge: 'STRICT',
    description: 'Higher sensitivity to formal AI syntax, light paraphrasing, and formulaic templates.',
  ),
  lenient(
    label: 'Creative Tolerant',
    badge: 'LENIENT',
    description: 'Higher tolerance for varied human styles, poetic prose, and unusual cadences.',
  );

  final String label;
  final String badge;
  final String description;

  const ForensicSensitivity({
    required this.label,
    required this.badge,
    required this.description,
  });

  static ForensicSensitivity fromName(String? name) {
    if (name == null) return ForensicSensitivity.balanced;
    return ForensicSensitivity.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ForensicSensitivity.balanced,
    );
  }
}
