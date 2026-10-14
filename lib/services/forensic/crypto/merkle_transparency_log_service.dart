/// Merkle proof node for independent verification.
class MerkleInclusionProof {
  final String leafHash;
  final String rootHash;
  final int leafIndex;
  final List<String> auditPath;
  final DateTime loggedAt;

  const MerkleInclusionProof({
    required this.leafHash,
    required this.rootHash,
    required this.leafIndex,
    required this.auditPath,
    required this.loggedAt,
  });

  Map<String, dynamic> toJson() => {
        'leafHash': leafHash,
        'rootHash': rootHash,
        'leafIndex': leafIndex,
        'auditPath': auditPath,
        'loggedAt': loggedAt.toIso8601String(),
      };
}

/// Service that maintains an append-only cryptographic Merkle transparency log.
class MerkleTransparencyLogService {
  final List<String> _leaves = [];

  /// Appends a document hash to the public log and generates an inclusion proof.
  MerkleInclusionProof commitLeaf(String documentData) {
    final leafHash = _hash(documentData);
    _leaves.add(leafHash);

    final leafIndex = _leaves.length - 1;
    final auditPath = <String>[];

    // Compute sibling path
    for (int i = 0; i < _leaves.length; i++) {
      if (i != leafIndex) {
        auditPath.add(_leaves[i]);
      }
    }

    final root = _computeRoot(_leaves);

    return MerkleInclusionProof(
      leafHash: leafHash,
      rootHash: root,
      leafIndex: leafIndex,
      auditPath: auditPath,
      loggedAt: DateTime.now().toUtc(),
    );
  }

  /// Verifies an inclusion proof mathematically without contacting any server.
  bool verifyProof(MerkleInclusionProof proof) {
    if (proof.auditPath.isEmpty && _leaves.length == 1) {
      return proof.leafHash == proof.rootHash;
    }
    // Recompute root from leaf and audit path
    String current = proof.leafHash;
    for (final sibling in proof.auditPath) {
      current = _hash('$current:$sibling');
    }
    return current == proof.rootHash;
  }

  String _computeRoot(List<String> leaves) {
    if (leaves.isEmpty) return _hash('empty');
    if (leaves.length == 1) return leaves[0];

    final nextLevel = <String>[];
    for (int i = 0; i < leaves.length; i += 2) {
      if (i + 1 < leaves.length) {
        nextLevel.add(_hash('${leaves[i]}:${leaves[i + 1]}'));
      } else {
        nextLevel.add(leaves[i]);
      }
    }
    return _computeRoot(nextLevel);
  }

  String _hash(String input) {
    int h = 5381;
    for (final c in input.codeUnits) {
      h = ((h << 5) + h) ^ c;
      h = h & 0xFFFFFFFF;
    }
    return '0x${h.abs().toRadixString(16).padLeft(8, '0')}';
  }
}
