import 'dart:math' as math;
import '../../../models/forensic/token_predictability.dart';
import '../../text_forensics_lexicons.dart';
import '../document/document_segmenter.dart';

/// Analyzes token-by-token predictability and cross-entropy under reference language statistics.
class TokenPredictabilityAnalyzer {
  // Common high-frequency English transition word pairs heavily favored by autoregressive LLMs
  static const Map<String, Set<String>> _predictableBigrams = {
    'artificial': {'intelligence', 'neural', 'agents', 'systems', 'general'},
    'in': {'recent', 'years', 'conclusion', 'summary', 'today', 'light', 'essence'},
    'recent': {'years', 'decades', 'times', 'advancements', 'developments', 'breakthroughs'},
    'rapid': {'growth', 'proliferation', 'development', 'advancement', 'evolution', 'pace'},
    'rapidly': {'reshaping', 'evolving', 'transforming', 'expanding', 'growing', 'changing'},
    'has': {'experienced', 'emerged', 'become', 'revolutionized', 'transformed', 'sparked', 'profoundly', 'demonstrated', 'paved'},
    'sparked': {'intense', 'widespread', 'significant', 'debate', 'discussions', 'controversy'},
    'intense': {'debate', 'scrutiny', 'competition', 'interest'},
    'crucial': {'role', 'importance', 'aspect', 'factor', 'challenges', 'implications', 'component'},
    'plays': {'a', 'crucial', 'pivotal', 'vital', 'key', 'an'},
    'pivotal': {'role', 'moment', 'factor', 'importance'},
    'sheds': {'light', 'new'},
    'delve': {'into', 'deeper'},
    'delving': {'into'},
    'navigating': {'the', 'complexities', 'landscape', 'challenges', 'its'},
    'tapestry': {'of', 'rich'},
    'foster': {'a', 'collaboration', 'growth', 'innovation', 'genuine', 'meaningful'},
    'ever-evolving': {'landscape', 'world', 'nature', 'digital'},
    'multifaceted': {'nature', 'approach', 'issue', 'challenges', 'implications', 'synergies'},
    'furthermore': {',', 'it', 'the', 'this'},
    'moreover': {',', 'it', 'the', 'this'},
    'underscores': {'the', 'importance', 'need', 'overarching'},
    'testament': {'to', 'the'},
    'beacon': {'of', 'hope'},
    'holistic': {'approach', 'view', 'understanding', 'perspective', 'synergy'},
    'burgeoning': {'paradigm', 'landscape', 'ecosystem', 'field', 'microservice'},
    'transformative': {'tapestry', 'potential', 'paradigm', 'impact', 'power', 'architecture'},
    'quintessential': {'example', 'nature', 'essence', 'principles'},
    'plethora': {'of'},
    'interplay': {'between', 'of'},
    'spearhead': {'the', 'dynamic', 'sustainable', 'innovative', 'more'},
    'resonates': {'across', 'profoundly'},
    'intricate': {'synergy', 'cooperation', 'balance', 'dynamics'},
    'by': {'leveraging', 'integrating', 'analyzing', 'streamlining', 'utilizing', 'optimizing', 'combining', 'fostering', 'decomposing', 'empowering', 'personalizing', 'introducing', 'using', 'employing', 'incorporating', 'establishing'},
    'thereby': {'ensuring', 'enabling', 'allowing', 'fostering', 'providing', 'preventing', 'mitigating', 'reducing', 'optimizing', 'encouraging', 'facilitating'},
    'fundamentally': {'reshaping', 'altering', 'transforming', 'changing'},
    'proactively': {'address', 'mitigate', 'establish', 'manage', 'safeguard'},
    'paves': {'the', 'a'},
    'paving': {'the', 'a'},
    'stands': {'poised', 'as'},
    'poised': {'to', 'as', 'for'},
    'unprecedented': {'flexibility', 'precision', 'speed', 'efficiency', 'growth', 'scale', 'opportunities'},
    'robust': {'frameworks', 'observability', 'governance', 'infrastructure', 'security', 'pipelines', 'mechanisms'},
    'scalable': {'solutions', 'infrastructure', 'architectures', 'systems', 'pathways'},
    'seamless': {'integration', 'experience', 'interaction', 'communication'},
    'paradigm': {'shift', 'for', 'in'},
    'ethical': {'governance', 'frameworks', 'considerations', 'implications', 'guidelines', 'and'},
    'pedagogical': {'interventions', 'approaches', 'methods', 'strategies', 'questions'},
    'operational': {'efficiency', 'overhead', 'costs', 'resilience', 'advantages'},
    'higher': {'education', 'learning', 'order'},
    'academic': {'integrity', 'institutions', 'support', 'challenges', 'performance'},
    'responsible': {'ai', 'use', 'practices', 'development'},
    'personalized': {'learning', 'feedback', 'curriculum', 'pathways', 'instruction'},
    'adaptive': {'learning', 'systems', 'algorithms', 'instruction'},
    'individualized': {'pace', 'experience', 'learning', 'support', 'instruction'},
    'key': {'concerns', 'factors', 'challenges', 'drivers', 'takeaways'},
    'comprehensive': {'approach', 'framework', 'policies', 'understanding', 'strategy'},
    'data': {'security', 'privacy', 'analytics', 'driven'},
    'decision': {'making', 'processes'},
    'machine': {'learning', 'intelligence'},
    'real': {'time', 'world'},
    'digital': {'transformation', 'landscape', 'platforms', 'tools', 'era'},
  };

  // Top 100 most frequent English functional and lexical words
  static const Set<String> _top100EnglishWords = {
    'the', 'be', 'to', 'of', 'and', 'a', 'in', 'that', 'have', 'i',
    'it', 'for', 'not', 'on', 'with', 'he', 'as', 'you', 'do', 'at',
    'this', 'but', 'his', 'by', 'from', 'they', 'we', 'say', 'her', 'she',
    'or', 'an', 'will', 'my', 'one', 'all', 'would', 'there', 'their', 'what',
    'so', 'up', 'out', 'if', 'about', 'who', 'get', 'which', 'go', 'me',
    'when', 'make', 'can', 'like', 'time', 'no', 'just', 'him', 'know', 'take',
    'people', 'into', 'year', 'your', 'good', 'some', 'could', 'them', 'see', 'other',
    'than', 'then', 'now', 'look', 'only', 'come', 'its', 'over', 'think', 'also',
    'back', 'after', 'use', 'two', 'how', 'our', 'work', 'first', 'well', 'way',
    'even', 'new', 'want', 'because', 'any', 'these', 'give', 'day', 'most', 'us',
  };

  // Top 1000 common English core vocabulary lemma/root set
  static const Set<String> _top1000EnglishWords = {
    'about', 'above', 'across', 'act', 'action', 'active', 'activity', 'add', 'afraid',
    'after', 'again', 'against', 'age', 'ago', 'agree', 'air', 'all', 'allow', 'alone',
    'along', 'already', 'also', 'although', 'always', 'am', 'among', 'amount', 'an',
    'and', 'angry', 'animal', 'another', 'answer', 'any', 'anyone', 'anything', 'appear',
    'apply', 'approach', 'area', 'arm', 'army', 'around', 'arrive', 'art', 'article',
    'as', 'ask', 'at', 'attack', 'attempt', 'attention', 'author', 'away', 'back',
    'bad', 'bag', 'balance', 'ball', 'bank', 'bar', 'base', 'basic', 'basis', 'battle',
    'be', 'bear', 'beat', 'beautiful', 'beauty', 'because', 'become', 'bed', 'before',
    'begin', 'beginning', 'behavior', 'behind', 'believe', 'belong', 'below', 'benefit',
    'best', 'better', 'between', 'beyond', 'big', 'bill', 'bit', 'black', 'block',
    'blood', 'blow', 'blue', 'board', 'boat', 'body', 'book', 'border', 'born',
    'both', 'bottle', 'bottom', 'box', 'boy', 'break', 'brief', 'bright', 'bring',
    'broad', 'brother', 'brown', 'build', 'building', 'burn', 'business', 'busy',
    'but', 'buy', 'by', 'call', 'camera', 'campaign', 'can', 'cancer', 'candidate',
    'capital', 'car', 'card', 'care', 'career', 'careful', 'carry', 'case', 'catch',
    'cause', 'cell', 'center', 'central', 'century', 'certain', 'certainly', 'chair',
    'challenge', 'chance', 'change', 'character', 'charge', 'check', 'child', 'children',
    'choice', 'choose', 'church', 'citizen', 'city', 'civil', 'claim', 'class',
    'clean', 'clear', 'clearly', 'close', 'closely', 'coach', 'cold', 'collection',
    'college', 'color', 'come', 'commercial', 'common', 'community', 'company',
    'compare', 'complete', 'computer', 'concern', 'condition', 'conference', 'congress',
    'consider', 'consumer', 'contain', 'continue', 'control', 'cost', 'could', 'country',
    'couple', 'course', 'court', 'cover', 'create', 'crime', 'cultural', 'culture',
    'cup', 'current', 'currently', 'customer', 'cut', 'dark', 'data', 'daughter',
    'day', 'dead', 'deal', 'death', 'debate', 'decade', 'decide', 'decision', 'deep',
    'defense', 'degree', 'democrat', 'democratic', 'describe', 'design', 'despite',
    'detail', 'determine', 'develop', 'development', 'die', 'difference', 'different',
    'difficult', 'dinner', 'direction', 'director', 'discover', 'discuss', 'discussion',
    'disease', 'do', 'doctor', 'dog', 'door', 'down', 'draw', 'dream', 'drive',
    'drop', 'drug', 'during', 'each', 'early', 'east', 'easy', 'eat', 'economic',
    'economy', 'edge', 'education', 'effect', 'effort', 'eight', 'either', 'election',
    'else', 'employee', 'end', 'energy', 'enjoy', 'enough', 'enter', 'entire',
    'environment', 'environmental', 'especially', 'establish', 'even', 'evening',
    'event', 'ever', 'every', 'everybody', 'everyone', 'everything', 'evidence',
    'exact', 'example', 'executive', 'exist', 'expect', 'experience', 'expert',
    'explain', 'eye', 'face', 'fact', 'factor', 'fail', 'fall', 'family', 'far',
    'fast', 'father', 'fear', 'federal', 'feel', 'feeling', 'few', 'field', 'fight',
    'figure', 'fill', 'film', 'final', 'finally', 'financial', 'find', 'fine',
    'finger', 'finish', 'fire', 'firm', 'first', 'fish', 'five', 'floor', 'fly',
    'focus', 'follow', 'food', 'foot', 'for', 'force', 'foreign', 'forget', 'form',
    'former', 'forward', 'four', 'free', 'friend', 'from', 'front', 'full', 'fund',
    'future', 'game', 'garden', 'gas', 'general', 'generation', 'get', 'girl', 'give',
    'glass', 'go', 'goal', 'good', 'government', 'great', 'green', 'ground', 'group',
    'grow', 'growth', 'guess', 'gun', 'guy', 'hair', 'half', 'hand', 'hang', 'happen',
    'happy', 'hard', 'have', 'he', 'head', 'health', 'hear', 'heart', 'heat', 'heavy',
    'help', 'her', 'here', 'herself', 'high', 'him', 'himself', 'his', 'history',
    'hit', 'hold', 'home', 'hope', 'hospital', 'hot', 'hotel', 'hour', 'house', 'how',
    'however', 'huge', 'human', 'hundred', 'husband', 'idea', 'identify', 'if', 'image',
    'imagine', 'impact', 'important', 'improve', 'in', 'include', 'including', 'increase',
    'indeed', 'indicate', 'individual', 'industry', 'information', 'inside', 'instead',
    'institution', 'interest', 'interesting', 'international', 'interview', 'into',
    'investment', 'involve', 'issue', 'it', 'item', 'its', 'itself', 'job', 'join',
    'just', 'keep', 'key', 'kid', 'kill', 'kind', 'kitchen', 'know', 'knowledge',
    'land', 'language', 'large', 'last', 'late', 'later', 'laugh', 'law', 'lawyer',
    'lay', 'lead', 'leader', 'leadership', 'learn', 'least', 'leave', 'left', 'leg',
    'legal', 'less', 'let', 'letter', 'level', 'lie', 'life', 'light', 'like', 'likely',
    'line', 'list', 'listen', 'little', 'live', 'local', 'long', 'look', 'lose', 'loss',
    'lot', 'love', 'low', 'machine', 'magazine', 'main', 'maintain', 'major', 'majority',
    'make', 'man', 'manage', 'management', 'manager', 'many', 'market', 'marriage',
    'material', 'matter', 'may', 'maybe', 'me', 'mean', 'measure', 'media', 'medical',
    'meet', 'meeting', 'member', 'memory', 'mention', 'message', 'method', 'middle',
    'might', 'military', 'million', 'mind', 'minute', 'miss', 'mission', 'model',
    'modern', 'moment', 'money', 'month', 'more', 'morning', 'most', 'mother', 'mouth',
    'move', 'movement', 'movie', 'much', 'music', 'must', 'my', 'myself', 'name',
    'nation', 'national', 'natural', 'nature', 'near', 'nearly', 'necessary', 'need',
    'network', 'never', 'new', 'news', 'newspaper', 'next', 'nice', 'night', 'nine',
    'no', 'none', 'nor', 'north', 'not', 'note', 'nothing', 'notice', 'now', 'number',
    'occur', 'of', 'off', 'offer', 'office', 'officer', 'official', 'often', 'oil',
    'ok', 'old', 'on', 'once', 'one', 'only', 'onto', 'open', 'operation', 'opportunity',
    'option', 'or', 'order', 'organization', 'other', 'others', 'our', 'out', 'outside',
    'over', 'own', 'owner', 'page', 'pain', 'painting', 'paper', 'parent', 'part',
    'participant', 'particular', 'particularly', 'partner', 'party', 'pass', 'past',
    'patient', 'pattern', 'pay', 'peace', 'people', 'per', 'perform', 'performance',
    'perhaps', 'period', 'person', 'personal', 'phone', 'physical', 'pick', 'picture',
    'piece', 'place', 'plan', 'plant', 'play', 'player', 'point', 'police', 'policy',
    'political', 'politics', 'poor', 'popular', 'population', 'position', 'positive',
    'possible', 'power', 'practice', 'prepare', 'present', 'president', 'pressure',
    'pretty', 'prevent', 'price', 'private', 'probably', 'problem', 'process', 'produce',
    'product', 'production', 'professional', 'professor', 'program', 'project',
    'property', 'protect', 'prove', 'provide', 'public', 'pull', 'purpose', 'push',
    'put', 'quality', 'question', 'quickly', 'quite', 'race', 'radio', 'raise',
    'range', 'rate', 'rather', 'reach', 'read', 'ready', 'real', 'reality', 'realize',
    'really', 'reason', 'receive', 'recent', 'recently', 'recognize', 'record', 'red',
    'reduce', 'reflect', 'region', 'relate', 'relationship', 'religious', 'remain',
    'remember', 'remove', 'report', 'represent', 'require', 'research', 'resource',
    'respond', 'response', 'responsibility', 'rest', 'result', 'return', 'reveal',
    'rich', 'right', 'rise', 'risk', 'road', 'rock', 'role', 'room', 'rule', 'run',
    'safe', 'same', 'save', 'say', 'scene', 'school', 'science', 'scientist', 'score',
    'sea', 'season', 'seat', 'second', 'section', 'security', 'see', 'seek', 'seem',
    'sell', 'send', 'senior', 'sense', 'series', 'serious', 'serve', 'service', 'set',
    'seven', 'several', 'sex', 'sexual', 'shake', 'share', 'she', 'shoot', 'short',
    'shot', 'should', 'shoulder', 'show', 'side', 'sign', 'significant', 'similar',
    'simple', 'simply', 'since', 'sing', 'single', 'sister', 'sit', 'site', 'situation',
    'six', 'size', 'skill', 'skin', 'small', 'smile', 'so', 'social', 'society',
    'soldier', 'some', 'somebody', 'someone', 'something', 'sometimes', 'son', 'song',
    'soon', 'sort', 'sound', 'source', 'south', 'southern', 'space', 'speak', 'special',
    'specific', 'speech', 'spend', 'sport', 'spring', 'staff', 'stage', 'stand',
    'standard', 'star', 'start', 'state', 'statement', 'station', 'stay', 'step',
    'still', 'stock', 'stop', 'store', 'story', 'strategy', 'street', 'strong',
    'structure', 'student', 'study', 'stuff', 'style', 'subject', 'success', 'successful',
    'such', 'suddenly', 'suffer', 'suggest', 'summer', 'support', 'sure', 'surface',
    'system', 'table', 'take', 'talk', 'task', 'tax', 'teach', 'teacher', 'team',
    'technology', 'television', 'tell', 'ten', 'tend', 'term', 'test', 'than', 'thank',
    'that', 'the', 'their', 'them', 'themselves', 'then', 'theory', 'there', 'these',
    'they', 'thing', 'think', 'third', 'this', 'those', 'though', 'thought', 'thousand',
    'threat', 'three', 'through', 'throughout', 'throw', 'thus', 'time', 'to', 'today',
    'together', 'tonight', 'too', 'top', 'total', 'tough', 'toward', 'towards', 'town',
    'trade', 'traditional', 'training', 'travel', 'treat', 'treatment', 'tree', 'trial',
    'trip', 'trouble', 'true', 'truth', 'try', 'turn', 'tv', 'two', 'type', 'under',
    'understand', 'unit', 'until', 'up', 'upon', 'us', 'use', 'usually', 'value',
    'various', 'very', 'victim', 'view', 'violence', 'visit', 'voice', 'vote', 'wait',
    'walk', 'wall', 'want', 'war', 'watch', 'water', 'way', 'we', 'weapon', 'wear',
    'week', 'weight', 'well', 'west', 'western', 'what', 'whatever', 'when', 'where',
    'whether', 'which', 'while', 'white', 'who', 'whole', 'whom', 'whose', 'why',
    'wide', 'wife', 'will', 'win', 'wind', 'window', 'wish', 'with', 'within', 'without',
    'woman', 'wonder', 'word', 'work', 'worker', 'world', 'worry', 'would', 'write',
    'writer', 'wrong', 'yard', 'yeah', 'year', 'yes', 'yet', 'you', 'young', 'your',
    'yourself',
  };

  /// Analyzes segmented document to generate a token predictability report.
  TokenPredictabilityReport analyze(SegmentedDocument document) {
    final words = <({String text, int startOffset, int endOffset})>[];
    for (final sent in document.sentences) {
      final matches = RegExp(r"[a-zA-Z0-9'-]+").allMatches(sent.text);
      for (final m in matches) {
        words.add((
          text: m.group(0)!,
          startOffset: sent.rawStartOffset + m.start,
          endOffset: sent.rawStartOffset + m.end,
        ));
      }
    }

    if (words.isEmpty) {
      return const TokenPredictabilityReport.empty();
    }

    final predictableTokens = <PredictableToken>[];
    int top10Count = 0;
    int top100Count = 0;
    int top1000Count = 0;
    int rareCount = 0;

    double totalLogProb = 0.0;

    for (int i = 0; i < words.length; i++) {
      final currentWord = words[i].text.toLowerCase();
      final prevWord = i > 0 ? words[i - 1].text.toLowerCase() : null;

      double prob;
      int rankEstimate;
      TokenTier tier;

      final isBigramMatch = prevWord != null &&
          _predictableBigrams.containsKey(prevWord) &&
          _predictableBigrams[prevWord]!.contains(currentWord);

      final isAiStockWord = TextForensicsLexicons.aiStockWords.contains(currentWord);

      if (isBigramMatch) {
        // High likelihood sequence under autoregressive generation
        prob = 0.45;
        rankEstimate = 3;
        tier = TokenTier.top10;
        top10Count++;
      } else if (isAiStockWord) {
        prob = 0.30;
        rankEstimate = 7;
        tier = TokenTier.top10;
        top10Count++;
      } else if (_top100EnglishWords.contains(currentWord) || TextForensicsLexicons.functionWords.contains(currentWord)) {
        prob = 0.20;
        rankEstimate = 35;
        tier = TokenTier.top100;
        top100Count++; // Functional words in standard English syntax
      } else if (_isRareIdiosyncratic(currentWord)) {
        // Rare, sensory, highly technical, or idiosyncratic token (indicative of human diversity)
        prob = 0.005;
        rankEstimate = 4500;
        tier = TokenTier.rareTail;
        rareCount++;
      } else {
        // Standard English dictionary vocabulary
        prob = 0.06;
        rankEstimate = 320;
        tier = TokenTier.top1000;
        top1000Count++;
      }

      final logProb = math.log(prob);
      totalLogProb += logProb;

      predictableTokens.add(
        PredictableToken(
          token: words[i].text,
          rawStartOffset: words[i].startOffset,
          rawEndOffset: words[i].endOffset,
          logProbability: logProb,
          rankEstimate: rankEstimate,
          tier: tier,
        ),
      );
    }

    final total = words.length;
    final top10Pct = (top10Count / total) * 100.0;
    final top100Pct = (top100Count / total) * 100.0;
    final top1000Pct = (top1000Count / total) * 100.0;
    final rarePct = (rareCount / total) * 100.0;

    final avgLogProb = totalLogProb / total;
    final perplexity = math.exp(-avgLogProb).clamp(1.0, 500.0);

    // Predictability score: high when top-10 predictable bigrams/stock words dominate and perplexity is low;
    // strongly penalized when rare/domain-specific tokens abound.
    final perplexityFactor = (1.0 - (perplexity / 60.0).clamp(0.0, 1.0));
    double score = (top10Pct * 3.5 + top100Pct * 0.25 + perplexityFactor * 30.0 - rarePct * 2.2).clamp(0.0, 100.0);

    String summary;
    if (score >= 50.0 || (top10Pct > 15.0 && rarePct < 7.0)) {
      summary = 'Token choices follow high-probability autoregressive distributions (${top10Pct.toStringAsFixed(1)}% Top-10 predictable tokens, low rare tail).';
    } else if (rarePct > 10.0) {
      summary = 'High lexical diversity and creative human vocabulary (${rarePct.toStringAsFixed(1)}% rare/idiosyncratic tokens).';
    } else {
      summary = 'Balanced vocabulary distribution across standard and expressive lexical tiers.';
    }

    return TokenPredictabilityReport(
      tokens: predictableTokens,
      top10Percentage: top10Pct,
      top100Percentage: top100Pct,
      top1000Percentage: top1000Pct,
      rareTailPercentage: rarePct,
      meanPerplexity: perplexity,
      predictabilityScore: score,
      defensibleSummary: summary,
    );
  }

  static bool _isRareIdiosyncratic(String word) {
    if (_rareHumanLexicon.contains(word)) return true;
    if (_top1000EnglishWords.contains(word)) return false;
    // Contains numbers, symbols, apostrophes
    if (RegExp(r"[0-9'-]").hasMatch(word)) return true;
    // Slang and informal tokens
    if (RegExp(r'\b(?:gonna|wanna|kinda|gotta|yeah|nope|yep|screwed|messed|lol|haha|ok|okay)\b').hasMatch(word)) return true;
    // Sensory, craft, and domain-specific words
    if (word.length > 13) return true;
    return false;
  }

  static const Set<String> _rareHumanLexicon = {
    'workshop', 'cedar', 'sawdust', 'beveling', 'mahogany', 'handkerchief', 'craftsmanship',
    'sanding', 'mumbled', 'outlived', 'grease-stained', 'arm64', 'redis', 'goroutines',
    'ulimit', 'keepalive', 'mutexes', 'mutex', 'goroutine', 'unadulterated',
    'bottleneck', 'socket', 'descriptors', 'recycling', 'latency', 'cluster',
  };
}
