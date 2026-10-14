TASK: Upgrade Lauriva's Humanizer skill to a production-quality v5.0.0.

ROLE:
Act as a senior AI systems engineer, computational linguist, technical writer, and prompt-engineering specialist. Your job is to improve the existing Humanizer skill's actual editing capabilities, not merely shorten the Markdown or increase its line count.

CONTEXT:
Lauriva is a writing assistant with an AI-authorship forensic analysis system. The Humanizer should improve the clarity, specificity, readability, flow, and naturalness of writing while preserving the author's meaning, evidence, intended voice, and appropriate writing style.

I want the skill to be comprehensive, precise, maintainable, and suitable for integration into a production application.

IMPORTANT:
Inspect the existing Humanizer skill before making changes. If both the original skill and a condensed or enhanced version are available, compare them. Do not assume that the shorter version is better simply because it is more concise.

OBJECTIVE 1 — PRESERVE VALUABLE COVERAGE

Audit the current skill for:
- Detailed writing-pattern rules.
- Examples of weak writing and improved alternatives.
- Sentence-level editing techniques.
- Paragraph-level structural improvements.
- Academic and technical writing requirements.
- Genre-specific differences.
- Voice calibration.
- Editing intensity and length controls.
- Exceptions where a pattern should remain unchanged.
- Edge cases and safeguards.
- Workflow instructions and quality checks.

Identify useful instructions that were removed, weakened, or oversimplified during previous revisions.

Restore valuable missing material. Consolidate genuine duplication, but do not remove a rule simply because it resembles another rule. Two similar rules may address different situations.

Preserve the original skill's useful terminology and organization where practical.

Do not blindly restore every old instruction. Improve rules that are redundant, contradictory, overly rigid, or unsupported.

OBJECTIVE 2 — BUILD A COMPREHENSIVE WRITING-QUALITY FRAMEWORK

Organize the skill into clear editing dimensions.

A. WORD AND PHRASE LEVEL
Review:
- Generic or inflated vocabulary.
- Empty intensifiers.
- Repeated words and phrases.
- Unnecessary nominalizations.
- Excessive hedging.
- Vague subjects and verbs.
- Stock expressions.
- Unnatural collocations.
- Repetitive transitions.
- Unnecessary disclaimers.
- Wordiness and filler.
- Unsupported interpretations attached to factual statements.
- Unnecessary contrast constructions.
- Formulaic three-part lists.
- Overuse of em dashes, semicolons, parentheses, and colons.
- Excessive adverbs.
- Repeated introductory phrases.
- Artificially polished or promotional language.

B. SENTENCE LEVEL
Review:
- Repeated sentence openings.
- Uniform sentence lengths.
- Excessively long sentences.
- Choppy sentences.
- Unnatural clause ordering.
- Awkward coordination and subordination.
- Unclear pronoun references.
- Weak verbs.
- Unnecessary passive voice.
- Unnatural parallelism.
- Repeated sentence templates.
- Redundant explanations.
- Incorrect logical relationships.
- Missing subjects or actors where they matter.

C. PARAGRAPH LEVEL
Review:
- Repeated topic-sentence structures.
- Paragraphs that repeat the same claim.
- Generic opening sentences.
- Conclusions that merely repeat introductions.
- Unsupported transitions between ideas.
- Paragraphs with several unrelated purposes.
- Claims without adequate explanation.
- Examples that are never interpreted.
- Evidence disconnected from the claim it supports.
- Repetitive paragraph endings.
- Excessive signposting.
- Paragraphs that sound individually polished but do not connect logically.

D. WHOLE-DOCUMENT LEVEL
Review:
- Formulaic introductions and conclusions.
- Repeated arguments across sections.
- Artificially symmetrical structures.
- Inconsistent tone.
- Sudden changes in vocabulary or formality.
- Unnecessary headings.
- Headings that repeat the following paragraph.
- Inconsistent terminology.
- Unsupported claims of importance.
- Weak overall progression.
- Missing reasoning between major points.
- Inconsistency between the thesis and conclusion.
- Repetition introduced by earlier editing passes.

For every major category, provide:
1. What to look for.
2. Why it can weaken the writing.
3. A weak example.
4. An improved example.
5. An exception or condition where the original construction should remain.

Examples must demonstrate genuine improvements in writing quality. Do not turn the framework into a list of words that must always be banned.

OBJECTIVE 3 — ADD A STRONGER EDITING WORKFLOW

Create a repeatable workflow with the following stages.

PASS 1: TASK AND CONSTRAINT ANALYSIS
Determine the intended audience, genre, tone, length, point of view, editing intensity, and output format.

Identify requirements involving quotations, citations, word counts, technical terminology, and structure.

Ask a question only when missing information materially prevents a correct edit.

PASS 2: BASELINE ANALYSIS
Read the entire input before rewriting.

Identify the central argument, supporting claims, evidence, important qualifications, and the author's existing voice.

Find the most significant writing problems rather than changing every sentence.

PASS 3: CONTENT AND LOGIC
Improve clarity and reasoning without inventing missing arguments.

Identify unsupported conclusions, unclear causal relationships, contradictions, missing explanations, and claims that need evidence.

Do not silently resolve factual uncertainty.

PASS 4: SENTENCE AND PARAGRAPH EDITING
Make targeted improvements to wording, grammar, rhythm, sentence structure, paragraph progression, and transitions.

Vary sentence structures naturally when doing so improves readability.

Do not deliberately introduce mistakes, awkward wording, random sentence lengths, slang, or unusual vocabulary to make the result appear human.

PASS 5: VOICE AND GENRE CALIBRATION
Match the requested register and any writing sample supplied by the user.

Do not make academic writing unnecessarily casual, professional writing overly conversational, or creative writing mechanically formal.

PASS 6: FIDELITY VERIFICATION
Compare the final version against the original.

Check names, numbers, dates, quotations, citations, claims, attributions, uncertainty, and logical relationships.

Identify any meaningful content changes.

PASS 7: FINAL QUALITY REVIEW
Read the complete revision as a coherent document.

Look for repetitive cadence, generic transitions, awkward edits, newly introduced repetition, unsupported claims, and inconsistent voice.

Undo changes that do not produce a meaningful improvement.

OBJECTIVE 4 — IMPROVE VOICE CALIBRATION

Support at least these modes:
- Academic.
- Professional.
- Technical.
- Conversational.
- Casual.
- Direct.
- Creative.
- Natural and balanced.

Allow users to specify a custom voice.

When a writing sample is supplied, analyze its relevant characteristics:
- Typical sentence length.
- Vocabulary complexity.
- Formality.
- Contractions.
- Punctuation preferences.
- Paragraph structure.
- First-person usage.
- Directness.
- Technical vocabulary.
- Preferred transitions.

Use these characteristics as guidance, not rigid numerical targets.

Do not copy distinctive sentences or transfer unsupported claims from the sample.

If no writing sample is available, do not pretend to know the author's personal voice. Use the requested genre and tone as the starting point.

OBJECTIVE 5 — SUPPORT DIFFERENT EDITING INTENSITIES

Define four explicit levels:

LEVEL 1: PROOFREAD
Correct spelling, grammar, punctuation, and obvious wording problems. Preserve the original wording wherever possible.

LEVEL 2: LIGHT EDIT
Improve awkward phrasing and minor repetition while retaining the original structure and voice.

LEVEL 3: DEEP EDIT
Rework sentences and paragraphs, remove redundant reasoning, improve transitions, and strengthen clarity while preserving the author's argument.

LEVEL 4: STRUCTURAL EDIT
Reorganize the document when necessary to improve argument progression and coherence. Flag missing evidence, unsupported reasoning, or substantive changes instead of silently inventing solutions.

Allow users to request a custom editing intensity.

Editing intensity must describe the extent of editing, not the probability of passing an AI detector.

OBJECTIVE 6 — PROTECT MEANING AND ACADEMIC INTEGRITY

Never:
- Invent quotations, citations, page numbers, sources, statistics, or personal experiences.
- Add false first-person reflections.
- Change an author's position without permission.
- Remove necessary uncertainty.
- Turn correlation into causation.
- Present speculation as established fact.
- Change the meaning of a quotation.
- Claim that paraphrasing eliminates the need for attribution.
- Replace specific reasoning with generic commentary.
- Add deliberate grammar errors to simulate human writing.
- Alter factual claims merely to increase stylistic variation.

When evidence is missing, identify the gap or insert an appropriate editorial placeholder.

Preserve existing citations and their relationships to the claims they support.

When asked to fact-check, distinguish factual corrections from stylistic edits.

OBJECTIVE 7 — HANDLE DIFFERENT TYPES OF INPUT

Provide explicit behavior for:
- Academic essays.
- Research papers.
- Reports.
- Business documents.
- Technical documentation.
- Emails and messages.
- Creative writing.
- Personal reflections.
- Short passages.
- Long documents.
- Text containing quotations.
- Text containing tables, code, or formulas.
- Text with a strict word limit.

Do not apply one universal writing style to all these categories.

For long inputs, preserve continuity across sections and avoid introducing inconsistencies between the introduction, body, and conclusion.

When only part of a document is provided, avoid claiming that the entire document has been reviewed.

OBJECTIVE 8 — MAKE THE SKILL OPERATIONALLY PRECISE

Every instruction should be actionable.

Replace vague instructions such as:
"Make the writing more natural."

With operational instructions such as:
"Identify repeated sentence openings across adjacent sentences. Change them only when repetition is distracting and an alternative preserves the meaning and emphasis."

Avoid contradictory instructions.

For example:
- Do not demand shorter writing while also requiring every explanation to be expanded.
- Do not require sentence-length variation in every paragraph.
- Do not remove every transition.
- Do not ban individual words or punctuation marks unconditionally.
- Do not require all paragraphs to have different structures.
- Do not change correct wording merely to produce a different version.

Make the default behavior conservative: retain effective sentences and edit where there is a clear benefit.

OBJECTIVE 9 — SEPARATE WRITING QUALITY FROM FORENSIC ANALYSIS

Lauriva has a separate AI-authorship forensic system.

The Humanizer should focus on:
- Clarity.
- Coherence.
- Specificity.
- Readability.
- Appropriate tone.
- Voice consistency.
- Grammar.
- Meaning preservation.

It should not claim to determine authorship from writing style alone.

Do not promise that a rewrite will receive a specific AI-detector score or become undetectable.

Do not optimize edits around detector thresholds, fabricated human mistakes, or arbitrary stylistic metrics.

Keep the Humanizer's output independent of any forensic classification result unless the product explicitly requires a separate, transparent workflow.

OBJECTIVE 10 — ADD A REAL VALIDATION FRAMEWORK

Create a test suite for the skill using representative examples from:
- Academic writing.
- Professional writing.
- Technical writing.
- Conversational writing.
- Creative writing.
- Short and long passages.
- Text with citations.
- Text with factual uncertainty.
- Text containing deliberate repetition.
- Text with a strong existing authorial voice.

For every test case, specify:
1. Input.
2. Editing objective.
3. Expected changes.
4. Elements that must remain unchanged.
5. Failure conditions.

Evaluate:
- Meaning preservation.
- Factual fidelity.
- Grammar.
- Readability.
- Logical coherence.
- Voice consistency.
- Genre suitability.
- Unnecessary rewriting.
- Unsupported additions.
- Citation preservation.

Use before-and-after examples and regression tests to identify whether a revision improves quality or simply changes wording.

Do not use a single AI-detector score as the measure of success.

DELIVERABLES

Produce:

1. A complete upgraded Humanizer skill, version 5.0.0.
2. A concise summary of the most important improvements.
3. A coverage audit showing which valuable rules were retained, restored, consolidated, or intentionally removed.
4. A list of any remaining limitations or assumptions.
5. A practical test suite with representative input/output examples and explicit preservation requirements.

IMPLEMENTATION REQUIREMENTS

- Inspect all available versions before editing.
- Preserve useful details from the original.
- Do not merely append new rules to the end.
- Remove genuine duplication without sacrificing coverage.
- Maintain valid Markdown and any required skill metadata format.
- Keep instructions easy for an LLM to follow.
- Use examples that illustrate the intended behavior.
- Do not claim tests passed unless they were actually executed.
- Do not change unrelated application files.
- If the skill is stored in a repository, inspect its existing integration and naming conventions before deciding where the new version belongs.
- If the existing skill has dependent files, update references only when necessary and verify that they remain consistent.
- Report the final file path and provide the complete updated skill.

FINAL ACCEPTANCE CRITERIA

The new version must be more capable, not merely longer.

It must preserve valuable original coverage, handle more writing scenarios, provide actionable editing rules, protect meaning and evidence, and include a practical way to validate quality.

Before finishing, compare the new version against the original and identify any valuable instruction that was accidentally lost.

Do not declare the task complete until the coverage audit and validation examples are included.