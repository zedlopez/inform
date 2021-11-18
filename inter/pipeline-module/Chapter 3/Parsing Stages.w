[ParsingStages::] Parsing Stages.

Two stages which look at raw I6-syntax material in the parse tree, either from
imsertions made using Inform 7's low-level features, or after reading the
source code for a kit.

@h Link.

=
void ParsingStages::create_pipeline_stage(void) {
	ParsingPipelines::new_stage(I"parse-kit", ParsingStages::run_parse_kit, TEMPLATE_FILE_STAGE_ARG, TRUE);	
	ParsingPipelines::new_stage(I"parse-insertions", ParsingStages::run_parse_insertions, NO_STAGE_ARG, FALSE);
}

int ParsingStages::run_parse_kit(pipeline_step *step) {
	inter_package *main_package = Site::main_package_if_it_exists(step->ephemera.repository);
	inter_bookmark IBM;
	if (main_package) {
		IBM = Inter::Bookmarks::at_end_of_this_package(main_package);
		if (Str::ne(step->step_argument, I"none")) {
			inter_tree *I = step->ephemera.repository;
			inter_symbol *module_name = PackageTypes::get(I, I"_module");
			inter_package *template_p = NULL;
			Inter::Package::new_package_named(&IBM, step->step_argument, FALSE,
				module_name, 1, NULL, &template_p);
			Site::set_assimilation_package(I, template_p);
		}
	} else IBM = Inter::Bookmarks::at_start_of_this_repository(step->ephemera.repository);
	ParsingStages::link(&IBM, step, I"all", step->ephemera.the_PP, NULL);
	return TRUE;
}

int ParsingStages::run_parse_insertions(pipeline_step *step) {
	inter_package *main_package = Site::main_package_if_it_exists(step->ephemera.repository);
	inter_bookmark IBM;
	if (main_package) IBM = Inter::Bookmarks::at_end_of_this_package(main_package);
	else IBM = Inter::Bookmarks::at_start_of_this_repository(step->ephemera.repository);
	ParsingStages::link(&IBM, step, I"none", step->ephemera.the_PP, NULL);
	return TRUE;
}

void ParsingStages::link(inter_bookmark *IBM, pipeline_step *step, text_stream *template_file, linked_list *PP, inter_package *owner) {
	if (IBM == NULL) internal_error("no inter to link with");
	inter_tree *I = Inter::Bookmarks::tree(IBM);
	if (Str::eq(template_file, I"none"))
		InterTree::traverse(I, ParsingStages::catch_all_visitor, NULL, NULL, 0);
	else
		InterTree::traverse(I, ParsingStages::visitor, NULL, NULL, 0);

	inter_package *template_package = Site::ensure_assimilation_package(I, RunningPipelines::get_symbol(step, plain_ptype_RPSYM));	
	
	inter_bookmark link_bookmark =
		Inter::Bookmarks::at_end_of_this_package(template_package);

	I6T_kit kit = TemplateReader::kit_out(&link_bookmark, &(ParsingStages::receive_raw),  &(ParsingStages::receive_command), NULL);
	kit.no_i6t_file_areas = LinkedLists::len(PP);
	pathname *P;
	int i=0;
	LOOP_OVER_LINKED_LIST(P, pathname, PP)
		kit.i6t_files[i] = Pathnames::down(P, I"Sections");
	int stage = EARLY_LINK_STAGE;
	if (Str::eq(template_file, I"none")) stage = CATCH_ALL_LINK_STAGE;
	TEMPORARY_TEXT(T)
	TemplateReader::I6T_file_intervene(T, stage, NULL, NULL, &kit);
	ParsingStages::receive_raw(T, &kit);
	DISCARD_TEXT(T)
	if (Str::ne(template_file, I"none"))
		TemplateReader::extract(template_file, &kit);
}

void ParsingStages::visitor(inter_tree *I, inter_tree_node *P, void *state) {
	if (P->W.data[ID_IFLD] == LINK_IST) {
		text_stream *S1 = Inode::ID_to_text(P, P->W.data[SEGMENT_LINK_IFLD]);
		text_stream *S2 = Inode::ID_to_text(P, P->W.data[PART_LINK_IFLD]);
		text_stream *S3 = Inode::ID_to_text(P, P->W.data[TO_RAW_LINK_IFLD]);
		text_stream *S4 = Inode::ID_to_text(P, P->W.data[TO_SEGMENT_LINK_IFLD]);
		void *ref = Inode::ID_to_ref(P, P->W.data[REF_LINK_IFLD]);
		TemplateReader::new_intervention((int) P->W.data[STAGE_LINK_IFLD], S1, S2, S3, S4, ref);
	}
}

void ParsingStages::catch_all_visitor(inter_tree *I, inter_tree_node *P, void *state) {
	if (P->W.data[ID_IFLD] == LINK_IST) {
		text_stream *S1 = NULL;
		text_stream *S2 = NULL;
		text_stream *S3 = Inode::ID_to_text(P, P->W.data[TO_RAW_LINK_IFLD]);
		text_stream *S4 = Inode::ID_to_text(P, P->W.data[TO_SEGMENT_LINK_IFLD]);
		void *ref = Inode::ID_to_ref(P, P->W.data[REF_LINK_IFLD]);
		TemplateReader::new_intervention((int) P->W.data[STAGE_LINK_IFLD], S1, S2, S3, S4, ref);
	}
}

void ParsingStages::entire_splat(inter_bookmark *IBM, text_stream *origin, text_stream *content, inter_ti level) {
	inter_ti SID = Inter::Warehouse::create_text(Inter::Bookmarks::warehouse(IBM), Inter::Bookmarks::package(IBM));
	text_stream *glob_storage = Inter::Warehouse::get_text(Inter::Bookmarks::warehouse(IBM), SID);
	Str::copy(glob_storage, content);
	Produce::guard(Inter::Splat::new(IBM, SID, 0, level, 0, NULL));
}

@

@d IGNORE_WS_FILTER_BIT 1
@d DQUOTED_FILTER_BIT 2
@d SQUOTED_FILTER_BIT 4
@d COMMENTED_FILTER_BIT 8
@d ROUTINED_FILTER_BIT 16
@d CONTENT_ON_LINE_FILTER_BIT 32

@d SUBORDINATE_FILTER_BITS (COMMENTED_FILTER_BIT + SQUOTED_FILTER_BIT + DQUOTED_FILTER_BIT + ROUTINED_FILTER_BIT)

=
void ParsingStages::receive_raw(text_stream *S, I6T_kit *kit) {
	text_stream *R = Str::new();
	int mode = IGNORE_WS_FILTER_BIT;
	LOOP_THROUGH_TEXT(pos, S) {
		wchar_t c = Str::get(pos);
		if ((c == 10) || (c == 13)) c = '\n';
		if (mode & IGNORE_WS_FILTER_BIT) {
			if ((c == '\n') || (Characters::is_whitespace(c))) continue;
			mode -= IGNORE_WS_FILTER_BIT;
		}
		if ((c == '!') && (!(mode & (DQUOTED_FILTER_BIT + SQUOTED_FILTER_BIT)))) {
			mode = mode | COMMENTED_FILTER_BIT;
		}
		if (mode & COMMENTED_FILTER_BIT) {
			if (c == '\n') {
				mode -= COMMENTED_FILTER_BIT;
				if (!(mode & CONTENT_ON_LINE_FILTER_BIT)) continue;
			}
			else continue;
		}
		if ((c == '[') && (!(mode & SUBORDINATE_FILTER_BITS))) {
			mode = mode | ROUTINED_FILTER_BIT;
		}
		if (mode & ROUTINED_FILTER_BIT) {
			if ((c == ']') && (!(mode & (DQUOTED_FILTER_BIT + SQUOTED_FILTER_BIT + COMMENTED_FILTER_BIT)))) mode -= ROUTINED_FILTER_BIT;
		}
		if ((c == '\'') && (!(mode & (DQUOTED_FILTER_BIT + COMMENTED_FILTER_BIT)))) {
			if (mode & SQUOTED_FILTER_BIT) mode -= SQUOTED_FILTER_BIT;
			else mode = mode | SQUOTED_FILTER_BIT;
		}
		if ((c == '\"') && (!(mode & (SQUOTED_FILTER_BIT + COMMENTED_FILTER_BIT)))) {
			if (mode & DQUOTED_FILTER_BIT) mode -= DQUOTED_FILTER_BIT;
			else mode = mode | DQUOTED_FILTER_BIT;
		}
		if (c != '\n') {
			if (Characters::is_whitespace(c) == FALSE) mode = mode | CONTENT_ON_LINE_FILTER_BIT;
		} else {
			if (mode & CONTENT_ON_LINE_FILTER_BIT) mode = mode - CONTENT_ON_LINE_FILTER_BIT;
			else if (!(mode & SUBORDINATE_FILTER_BITS)) continue;
		}
		PUT_TO(R, c);
		if ((c == ';') && (!(mode & SUBORDINATE_FILTER_BITS))) {
			ParsingStages::chunked_raw(R, kit);
			mode = IGNORE_WS_FILTER_BIT;
		}
	}
	ParsingStages::chunked_raw(R, kit);
	Str::clear(S);
}

void ParsingStages::chunked_raw(text_stream *S, I6T_kit *kit) {
	if (Str::len(S) == 0) return;
	PUT_TO(S, '\n');
	ParsingStages::entire_splat(kit->IBM, I"template", S, (inter_ti) (Inter::Bookmarks::baseline(kit->IBM) + 1));
	Str::clear(S);
}

void ParsingStages::receive_command(OUTPUT_STREAM, text_stream *command, text_stream *argument, I6T_kit *kit) {
	if ((Str::eq_wide_string(command, L"plugin")) ||
		(Str::eq_wide_string(command, L"type")) ||
		(Str::eq_wide_string(command, L"open-file")) ||
		(Str::eq_wide_string(command, L"close-file")) ||
		(Str::eq_wide_string(command, L"lines")) ||
		(Str::eq_wide_string(command, L"endlines")) ||
		(Str::eq_wide_string(command, L"open-index")) ||
		(Str::eq_wide_string(command, L"close-index")) ||
		(Str::eq_wide_string(command, L"index-page")) ||
		(Str::eq_wide_string(command, L"index-element")) ||
		(Str::eq_wide_string(command, L"index")) ||
		(Str::eq_wide_string(command, L"log")) ||
		(Str::eq_wide_string(command, L"log-phase")) ||
		(Str::eq_wide_string(command, L"progress-stage")) ||
		(Str::eq_wide_string(command, L"counter")) ||
		(Str::eq_wide_string(command, L"value")) ||
		(Str::eq_wide_string(command, L"read-assertions")) ||
		(Str::eq_wide_string(command, L"callv")) ||
		(Str::eq_wide_string(command, L"call")) ||
		(Str::eq_wide_string(command, L"array")) ||
		(Str::eq_wide_string(command, L"marker")) ||
		(Str::eq_wide_string(command, L"testing-routine")) ||
		(Str::eq_wide_string(command, L"testing-command"))) {
		LOG("command: <%S> argument: <%S>\n", command, argument);
		PipelineErrors::kit_error("the template command '{-%S}' has been withdrawn in this version of Inform", command);
	} else {
		LOG("command: <%S> argument: <%S>\n", command, argument);
		PipelineErrors::kit_error("no such {-command} as '%S'", command);
	}
}