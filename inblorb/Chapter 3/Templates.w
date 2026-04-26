[Templates::] Templates.

To manage templates for website generation.

@h Templates and their paths.
Template paths define, in order of priority, where to look for templates.

=
classdef template_path {
	struct pathname *template_repository; /* pathname of folder of repository */
}

@ Whereas templates are the things themselves.

=
classdef template {
	struct text_stream *template_name; /* e.g., "Standard" */
	struct template_path *template_location;
	struct pathname *template_pathname;
	struct filename *latest_use; /* filename most recently sought from it */
}

@h Defining template paths.
The following implements the Blurb command "template path".

=
int no_template_paths = 0;
void Templates::new_path(pathname *P) {
	template_path *tp = CREATE(template_path);
	tp->template_repository = P;
	if (verbose_mode)
		PRINT("! Template search path %d: <%p>\n", ++no_template_paths, P);
}

@ This would be a little inefficient except that it is needed relatively
few times, and on directories we can reasonably expect to have few entries.
The idea is to find a subdirectory from a path where we only know a
version of the name which may have the wrong casing: this is needed because
on Linux systems with case-sensitive file systems, the following will
otherwise not both work.

> Release along with a "parchment" interpreter.

> Release along with a "Parchment" interpreter.

=
pathname *Templates::best_path(pathname *P, text_stream *name) {
	TEMPORARY_TEXT(match)
	WRITE_TO(match, "%S%c", name, FOLDER_SEPARATOR);
	linked_list *L = Directories::listing(P);
	text_stream *candidate, *found = NULL;
	LOOP_OVER_LINKED_LIST(candidate, text_stream, L)
		if (Str::eq_insensitive(candidate, match))
			found = candidate;
	DISCARD_TEXT(match)
	if (found) {
		Str::delete_last_character(found);
		return Pathnames::down(P, found);
	}
	return NULL;
}

@ The following searches for a named file in a named template, returning
the template path which holds the template if it exists. This might look a
pretty odd thing to do — weren't we looking for the file itself? But the
answer is that `Templates::seek_file` is really used to detect
the presence of templates, not of files.

=
template_path *Templates::seek_file(text_stream *name, text_stream *leafname, pathname **at) {
	template_path *tp;
	LOOP_OVER(tp, template_path) {
		pathname *T = Templates::best_path(tp->template_repository, name);
		if (T) {
			filename *possible = Filenames::in(T, leafname);
			if (TextFiles::exists(possible)) {
				*at = T; return tp;
			}
		}
	}
	return NULL;
}

@ And this is where that happens. Suppose we need to locate the template
"Molybdenum". We do this by looking for a directory whose name matches that
case-insensitively, in any of our known potential locations for such
directories, _and_ which contains one of the files suggesting that this is
indeed a template, either for a website or an interpreter.

=
template *Templates::find(text_stream *name) {
	template *t;
	@<Is this a template we already know?@>;
	pathname *at = NULL;
	template_path *tp = Templates::seek_file(name, I"index.html", &at);
	if (tp == NULL) tp = Templates::seek_file(name, I"source.html", &at);
	if (tp == NULL) tp = Templates::seek_file(name, I"style.css", &at);
	if (tp == NULL) tp = Templates::seek_file(name, I"(extras).txt", &at);
	if (tp == NULL) tp = Templates::seek_file(name, I"(manifest).txt", &at);
	if (tp) {
		t = CREATE(template);
		t->template_name = Str::duplicate(name);
		t->template_location = tp;
		t->template_pathname = at;
		return t;
	}
	return NULL;
}

@ It reduces pointless file accesses to cache the results, so:

@<Is this a template we already know?@> =
	LOOP_OVER(t, template)
		if (Str::eq_insensitive(name, t->template_name))
			return t;

@h Searching for template files.
If we can't find the file `name` in the template specified, we try looking
inside "Standard" instead (if we can find a template of that name).

=
int template_doesnt_exist = FALSE;
filename *Templates::find_file_in_specific_template(text_stream *name, text_stream *needed) {
	template *t = Templates::find(name), *Standard = Templates::find(I"Standard");
	if (t == NULL) {
		if (template_doesnt_exist == FALSE) {
			BlorbErrors::errorf_1S(
				"Websites and play-in-browser interpreter web pages are created "
				"using named templates. (Basic examples are built into the Inform "
				"application. You can also create your own, putting them in the "
				"'Templates' subfolder of the project's Materials folder.) Each "
				"template has a name. On this Release, I tried to use the "
				"'%S' template, but couldn't find a copy of it anywhere.", name);
		}
		template_doesnt_exist = TRUE;
	}
	filename *path = Templates::try_single(t, needed);
	if ((path == NULL) && (Standard)) path = Templates::try_single(Standard, needed);
	return path;
}

@ Where, finally:

=
filename *Templates::try_single(template *t, text_stream *needed) {
	if (t == NULL) return NULL;

	t->latest_use = Filenames::in(t->template_pathname, needed);
	if (verbose_mode) PRINT("! Trying <%f>\n", t->latest_use);
	if (TextFiles::exists(t->latest_use)) return t->latest_use;
	return NULL;
}
