import '../../../../models/forensic/neural_detection_result.dart';
import '../../segmentation/sentence_segmenter.dart';

/// Tokenizer contract shared by every on-device detector vocabulary
/// (WordPiece for the English BERT-family models, SentencePiece Unigram for
/// the multilingual XLM-R-family models).
///
/// [tokenize] must return a fixed-length [TokenizedInput] (padded to
/// [maxSequenceLength]) with token spans as UTF-16 offsets into `text`, which
/// is all [NeuralDetectorService] and the inference runners consume.
abstract class NeuralTokenizer {
  /// Fixed tensor length every [tokenize] result is padded/truncated to.
  int get maxSequenceLength;

  /// Id used to pad `input_ids` beyond the real tokens.
  int get padTokenId;

  /// Id emitted for out-of-vocabulary text.
  int get unkTokenId;

  /// Tokenizes [text] preserving token spans and sentence associations.
  TokenizedInput tokenize({
    required String text,
    List<SentenceBoundary>? sentences,
  });
}
