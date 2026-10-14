import 'package:flutter_test/flutter_test.dart';
import 'package:lauriva/models/llm_provider.dart';

void main() {
  group('LlmGenerationParams.personaInstruction', () {
    // Every persona id offered to the user (HeaderBar quick-switch menu and
    // the Settings modal's "Writing Persona" chips) must resolve to a real,
    // distinct instruction. A persona that silently falls back to the
    // "standard" wording would look selectable in the UI while having zero
    // effect on the actual LLM output.
    const uiExposedPersonaIds = ['standard', 'executive', 'casual', 'academic', 'creative'];

    test('every UI-exposed persona id produces a non-empty instruction', () {
      for (final id in uiExposedPersonaIds) {
        final instruction = LlmGenerationParams(persona: id).personaInstruction;
        expect(instruction, isNotEmpty, reason: 'persona "$id" produced an empty instruction');
      }
    });

    test('every non-standard persona has a distinct instruction from standard', () {
      final standardInstruction = const LlmGenerationParams(persona: 'standard').personaInstruction;

      for (final id in uiExposedPersonaIds) {
        if (id == 'standard') continue;
        final instruction = LlmGenerationParams(persona: id).personaInstruction;
        expect(
          instruction,
          isNot(equals(standardInstruction)),
          reason: 'persona "$id" silently fell back to the standard instruction',
        );
      }
    });

    test('unknown persona ids fall back to the standard instruction', () {
      final standardInstruction = const LlmGenerationParams(persona: 'standard').personaInstruction;
      final unknownInstruction = LlmGenerationParams(persona: 'not_a_real_persona').personaInstruction;
      expect(unknownInstruction, standardInstruction);
    });
  });
}
