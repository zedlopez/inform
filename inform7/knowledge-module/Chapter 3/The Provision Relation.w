[ProvisionRelation::] The Provision Relation.

To define the provision relation, which determines which properties
can be held by which objects.

@ Assertions assigning properties ("A scene has a time called the expected
duration") generate propositions which assert that a subject, here "scene",
provides a property, here "expected duration". The relation needed is:

@<Global knowledge variable definitions@> +=
binary_predicate *R_provision = NULL;

@h Family.
There is just one provision relation, which is the only member of its family.

=
bp_family *provision_bp_family = NULL;

void ProvisionRelation::start(void) {
	provision_bp_family = BinaryPredicateFamilies::new();
	METHOD_ADD(provision_bp_family, STOCK_BPF_MTID, ProvisionRelation::stock);
	METHOD_ADD(provision_bp_family, TYPECHECK_BPF_MTID, ProvisionRelation::typecheck);
	METHOD_ADD(provision_bp_family, ASSERT_BPF_MTID, ProvisionRelation::assert);
	METHOD_ADD(provision_bp_family, SCHEMA_BPF_MTID, ProvisionRelation::schema);
	METHOD_ADD(provision_bp_family, DESCRIBE_FOR_INDEX_BPF_MTID,
		ProvisionRelation::describe_for_index);
}

@h Initial stock.
There's just one relation of this kind, and it's hard-wired in. The terms are
given a very broad range of what they can accept.

=
void ProvisionRelation::stock(bp_family *self, int n) {
	if (n == 1) {
		R_provision =
			BinaryPredicates::make_pair(provision_bp_family,
				BPTerms::new(NULL), BPTerms::new(NULL),
				I"provides", NULL, NULL, NULL,
				PreformUtilities::wording(<relation-names>, PROVISION_RELATION_NAME));
		BinaryPredicates::set_index_details(R_provision, "value", "property");
	}
}

@h Typechecking.
Any property can in principle be assigned to any inference subject, so there's
really no restriction on the left term. The right term, of course, has to be
a value property. It's surprisingly tricky to provide a good problem message
for the case where an either-or property has been quoted because that will have
been read adjectivally, so that term 1 here will be a variable ranging over
some kind (usually `object`) which might or might not have the either-or property:
in effect, `X provides open` is read as `X provides something open`. But we can't
see the whole proposition here, so we just have to make a guess at what might
be a good problem message.

=
int ProvisionRelation::typecheck(bp_family *self, binary_predicate *bp,
	pcalc_term *terms, kind **kinds_of_terms, kind **kinds_required, tc_problem_kit *tck) {
	if (Kinds::get_construct(kinds_of_terms[1]) == CON_property) return ALWAYS_MATCH;
	if ((terms[1].variable >= 0) && (Kinds::eq(kinds_of_terms[1], K_object))) {
		Problems::quote_kind(4, kinds_of_terms[1]);
		StandardProblems::tcp_problem(_p_(PM_BadProvidesEO), tck,
			"that asks whether something provides something, and in Inform 'to provide' "
			"means that an object (or value) has a property attached - for instance, "
			"containers provide the property 'carrying capacity'. But it has to be "
			"a property with a value, not an either-or property like 'open' or 'lighted'. "
			"This doesn't seem to be a property with a value.");
	} else {
		Problems::quote_kind(4, kinds_of_terms[1]);
		StandardProblems::tcp_problem(_p_(PM_BadProvides), tck,
			"that asks whether something provides something, and in Inform 'to provide' "
			"means that an object (or value) has a property attached - for instance, "
			"containers provide the property 'carrying capacity'. But it has to be "
			"a property with a value. Here, what comes after 'provides' is %4 "
			"rather than the name of a property with a value.");
	}
	return NEVER_MATCH;
}

@h Assertion.
If we assert that, say, vehicles provide "colour", then we are implicitly
enabling adjectives formed from its enumerated instances — say, "green" or
"blue" — can apply to vehicles, so we must make sure any such meanings are
defined.

=
int ProvisionRelation::assert(bp_family *self, binary_predicate *bp,
		inference_subject *infs0, parse_node *spec0,
		inference_subject *infs1, parse_node *spec1) {
	property *prn = Rvalues::to_property(spec1);
	if ((infs0) && (prn)) {
		PropertyPermissions::grant(infs0, prn, TRUE);
		Instances::update_adjectival_forms(prn);
		return TRUE;
	}
	return FALSE;
}

@h Compilation.
Run-time is too late to change which objects provide what, so this relation
can't be changed at compile time.

=
int ProvisionRelation::schema(bp_family *self, int task, binary_predicate *bp,
	annotated_i6_schema *asch) {
	if (task == TEST_ATOM_TASK) return RTProperties::test_provision_schema(asch);
	return FALSE;
}

@h Problem message text.
Nothing special is needed here.

=
void ProvisionRelation::describe_for_index(bp_family *self, OUTPUT_STREAM,
	binary_predicate *bp) {
	WRITE("provision");
}
