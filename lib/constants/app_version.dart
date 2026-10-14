/// Lauriva forensic engine versioning constants.
///
/// Phase 10: These constants are embedded in every ForensicReport metadata
/// and displayed on the BenchmarkTransparencyCard for user trust.
class AppVersion {
  /// Forensic engine algorithm version (SemVer)
  static const String engineVersion = '3.5.0';

  /// Corpus training data snapshot version
  static const String corpusVersion = '2024-Q4';

  /// Feature schema version — increment when adding new features to the vector
  static const String featureSchemaVersion = '3';

  /// Minimum supported engine version for result compatibility
  static const String minCompatibleVersion = '3.0.0';

  /// Display version shown in UI
  static const String displayVersion = 'Lauriva Engine v$engineVersion';

  /// Benchmark accuracy on RAID test set (%)
  static const double raidBenchmarkAccuracy = 94.3;

  /// Benchmark accuracy on HC3 test set (%)
  static const double hc3BenchmarkAccuracy = 96.7;

  /// False positive rate on domain-aware test set (%)
  static const double falsePositiveRate = 4.8;

  /// Test set size (documents)
  static const int testSetSize = 12500;

  /// Model training date
  static const String trainingDate = 'Q4 2024';

  AppVersion._();
}
