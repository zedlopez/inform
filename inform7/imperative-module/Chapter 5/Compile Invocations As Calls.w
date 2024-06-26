[CallingFunctions::] Compile Invocations As Calls.

An invocation defined with Inform 7 source text is made with an Inter function call.

@ Compiling an invocation into a call to an Inter function is simple enough:

=
void CallingFunctions::csi_by_call(value_holster *VH, parse_node *inv,
	source_location *where_from, tokens_packet *tokens) {

	id_body *idb = Node::get_phrase_invoked(inv);

	inter_name *IS = PhraseRequests::complex_request(idb, tokens->fn_kind,
		Node::get_kind_variable_declarations(inv), Node::get_text(inv));
	LOGIF(MATCHING, "Calling function %n with kind %u from $e\n", IS,
		tokens->fn_kind, inv);

	int options_supplied = Invocations::get_phrase_options_bitmap(inv);
	if (Node::get_phrase_options_invoked(inv) == NULL) options_supplied = -1;

	if (VH->vhmode_wanted == INTER_VAL_VHMODE) VH->vhmode_provided = INTER_VAL_VHMODE;
	else VH->vhmode_provided = INTER_VOID_VHMODE;
	CallingFunctions::direct_function_call(tokens, IS, options_supplied);
}

@ The following can be used to call any phrase compiled to an I6 routine,
and it's used not only by the code above, but also when calling a
phrase value stored dynamically at run-time.

=
void CallingFunctions::direct_function_call(tokens_packet *tokens, inter_name *identifier,
	int phrase_options) {
	kind *return_kind = NULL;
	@<Compute the return kind of the phrase@>;

	EmitCode::call(identifier);
	EmitCode::down();
		@<Emit the comma-separated list of arguments@>;
	EmitCode::up();
}

@<Compute the return kind of the phrase@> =
	kind *K = tokens->fn_kind;
	if (Kinds::get_construct(K) != CON_phrase) internal_error("no function kind");
	Kinds::binary_construction_material(K, NULL, &return_kind);

@ If the return kind stores values on the heap, we must call the function with
a pointer to a new value of that kind as the first argument. Arguments corresponding
to the tokens then follow, and finally the optional bitmap of phrase options.

@<Emit the comma-separated list of arguments@> =
	if (Kinds::Behaviour::uses_block_values(return_kind))
		Frames::emit_new_local_value(return_kind);
	for (int k=0; k<tokens->tokens_count; k++)
		CompileValues::to_fresh_code_val_of_kind(tokens->token_vals[k], tokens->token_kinds[k]);
	if (phrase_options != -1)
		EmitCode::val_number((inter_ti) phrase_options);

@ The indirect version of the function is used when a function whose address
is not known at compile time must be called; this is needed in a few inline
invocations.

=
void CallingFunctions::indirect_function_call(tokens_packet *tokens,
	parse_node *indirect_spec, int lookup_flag) {
	kind *return_kind = NULL;
	@<Compute the return kind of the phrase@>;

	int arity = tokens->tokens_count;
	if (Kinds::Behaviour::uses_block_values(return_kind)) arity++;
	inter_ti BIP = Primitives::BIP_for_indirect_call_returning_value(arity);
	EmitCode::inv(BIP);
	EmitCode::down();
	if (lookup_flag) {
		EmitCode::inv(LOOKUP_BIP);
		EmitCode::down();
			CompileValues::to_code_val(indirect_spec);
			EmitCode::val_number(1);
		EmitCode::up();
	} else {
		CompileValues::to_code_val(indirect_spec);
	}
	int phrase_options = -1;
	@<Emit the comma-separated list of arguments@>;
	EmitCode::up();
}
