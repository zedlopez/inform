[TextLiterals::] Text Literals.

In this section we compile text constants.

@h Runtime representation.
Literal texts arise from source text such as:

``` Inform7
	let Q be "the quick brown fox";
	say "Where has that indolent hound got to?";
```

Note that only `"the quick brown fox"` is actually a constant value here; the
text concerning the hound is turned directly into operands for Inter instructions
for printing text, and never needs to be a value. The fox text, on the other hand,
is being stored in `Q`, and you can only store values.

Text at runtime is stored in small blocks, always of size 2:

``` None
	                    small block:
	Q ----------------> format
	                    content
```

The format can be one of five possible alternatives at runtime, and the runtime
system may dynamically switch between them; essentially it uses this to
decompress text from its "packed" form to a character-accessible form only
on demand.

The compiler generates only three of these formats: `CONSTANT_PACKED_TEXT_STORAGE`,
`CONSTANT_UNPACKED_TEXT_STORAGE` and `CONSTANT_PERISHABLE_TEXT_STORAGE_HL`.
For an explanation of the latter, see //Text Substitutions//.

In this format, the `content` can be either a packed string, or a function,
so although there is no long block to make, we do always have something else
to make besides the small block.

In this section, `content` will always be a packed string; in //Text Substitutions//
it will always be a function.

=
inter_name *TextLiterals::small_block(inter_name *content) {
	inter_name *small_block = Enclosures::new_small_block_for_constant();
	TextLiterals::compile_SB_array(small_block, content, FALSE);
	return small_block;
}

void TextLiterals::compile_SB_array(inter_name *at, inter_name *content, int perishable) {
	packaging_state save = EmitArrays::begin_unchecked(at);
	if (perishable)
		EmitArrays::iname_entry(Hierarchy::find(CONSTANT_PERISHABLE_TEXT_STORAGE_HL));
	else
		EmitArrays::iname_entry(Hierarchy::find(CONSTANT_PACKED_TEXT_STORAGE_HL));
	EmitArrays::iname_entry(content);
	EmitArrays::end(save);
}

inter_name *TextLiterals::long_block(inter_name *at, text_stream *whatever) {
	packaging_state save = EmitArrays::begin_unchecked(at);
	TheHeap::emit_block_value_header(K_text, TRUE, Str::len(whatever) + 1);
	for (int i=0; i<Str::len(whatever); i++)
		EmitArrays::numeric_entry(Str::get_at(whatever, i));
	EmitArrays::numeric_entry(0);
	EmitArrays::end(save);

	inter_name *small_block = Enclosures::new_small_block_for_constant();
	save = EmitArrays::begin_unchecked(small_block);
	EmitArrays::iname_entry(Hierarchy::find(CONSTANT_UNPACKED_TEXT_STORAGE_HL));
	EmitArrays::iname_entry(at);
	EmitArrays::end(save);

	return small_block;
}

@h Default value.
The default text is empty:

=
inter_name *TextLiterals::default_text(void) {
	return TextLiterals::small_block(Hierarchy::find(EMPTY_TEXT_PACKED_HL));
}

@h Suppressing apostrophe substitution.
We are allowed to flag one text where ordinary apostrophe-to-double-quote
substitution doesn't occur: this is used for the title at the top of the
source text, and nothing else.

=
int wn_quote_suppressed = -1;
void TextLiterals::suppress_quote_expansion(wording W) {
	wn_quote_suppressed = Wordings::first_wn(W);
}
int TextLiterals::suppressing_on(wording W) {
	if ((wn_quote_suppressed >= 0) &&
		(Wordings::first_wn(W) == wn_quote_suppressed)) return TRUE;
	return FALSE;
}

@h Making literals.
This was once a rather elegantly complicated algorithm involving searches on
a red-black tree in order to compile the texts in alphabetical order, but in
April 2021 that was replaced by an Inter pipeline stage which collates the text
much later in the process. See //pipeline: Literal Text//.

=
inter_name *TextLiterals::to_value(wording W) {
	return TextLiterals::to_value_inner(W, FALSE);
}

inter_name *TextLiterals::to_value_unescaped(wording W) {
	return TextLiterals::to_value_inner(W, TRUE);
}

inter_name *TextLiterals::to_value_inner(wording W, int unesc) {
	int w1 = Wordings::first_wn(W);
	if (Wide::cmp(Lexer::word_text(w1), U"\"\"") == 0)
		return TextLiterals::default_text();

	int unpacked = TRUE;
	if (TargetVMs::is_16_bit(Task::vm())) unpacked = FALSE;
	int lit = TEXT_LITERAL_HL;
	if (unpacked) lit = UTEXT_LITERAL_HL;

	inter_name *content_iname = Enclosures::new_iname(LITERALS_HAP, lit);
	if (Task::wraps_existing_storyfile()) {
		Emit::text_constant_literal(content_iname, I"--");
		return TextLiterals::small_block(content_iname);
	} else {
		TEMPORARY_TEXT(TLT)
		int options = CT_DEQUOTE;
		if (TextLiterals::suppressing_on(W) == FALSE) {
			if (unesc == FALSE) options += CT_EXPAND_APOSTROPHES;
			if (RTBibliographicData::in_bibliographic_mode()) {
				options += CT_RECOGNISE_APOSTROPHE_SUBSTITUTION;
				options += CT_RECOGNISE_UNICODE_SUBSTITUTION;
			}
		}
		if (unpacked) TranscodeText::from_wide_string_for_emission(TLT, Lexer::word_text(w1));
		else TranscodeText::from_wide_string(TLT, Lexer::word_text(w1), options);
		inter_name *result = NULL;
		if (unpacked) {
			result = TextLiterals::long_block(content_iname, TLT);
		} else {
			Emit::text_constant_literal(content_iname, TLT);
			result = TextLiterals::small_block(content_iname);
		}
		DISCARD_TEXT(TLT)
		return result;
	}
}
