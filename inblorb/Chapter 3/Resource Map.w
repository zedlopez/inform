[ResourceMap::] Resource Map.

@ The resource map is composed of entries like so:

=
classdef resource_map_entry {
	int is_picture; /* if not, is a sound */
	int resource_ID;
	struct filename *currently_at;
	struct text_stream *alt_text;
}

void ResourceMap::register_resource(int is_picture, int n, filename *fn, text_stream *alt) {
	resource_map_entry *entry = CREATE(resource_map_entry);
	entry->is_picture = is_picture;
	entry->resource_ID = n;
	entry->currently_at = fn;
	entry->alt_text = Str::duplicate(alt);
}

void ResourceMap::register_picture(int n, filename *fn, text_stream *alt) {
	ResourceMap::register_resource(TRUE, n, fn, alt);
}

void ResourceMap::register_sound(int n, filename *fn, text_stream *alt) {
	ResourceMap::register_resource(FALSE, n, fn, alt);
}

int ResourceMap::transfer_resource(int is_pictures, pathname *destination) {
	int ensured = FALSE, N = 0;
	resource_map_entry *entry;
	LOOP_OVER(entry, resource_map_entry) {
		filename *from = entry->currently_at;
		filename *to = Filenames::in(destination, Filenames::get_leafname(entry->currently_at));
		if (entry->is_picture == is_pictures) {
			if (ensured == FALSE) {
				if (Pathnames::create_in_file_system(destination) == FALSE) {
					BlorbErrors::error_1p(
						"You asked to copy resources to a directory which does not exist",
						destination);
					return 0;
				}	
				ensured = TRUE;
			}
			if (BinaryFiles::copy(from, to, TRUE) == -1)
				BlorbErrors::error_1f(
					"You asked to copy a resource to a file I can't create", to);
			else
				N++;
		}
	}
	return N;
}

void ResourceMap::transfer_pictures(pathname *destination) {
	int N = ResourceMap::transfer_resource(TRUE, destination);
	PRINT("Copied %d picture%s to %p\n", N, (N!=1)?"s":"", destination);
}

void ResourceMap::transfer_sounds(pathname *destination) {
	int N = ResourceMap::transfer_resource(FALSE, destination);
	PRINT("Copied %d sound%s to %p\n", N, (N!=1)?"s":"", destination);
}

@ Note that the URL in the resource map is relative to `play.html`, and is
given the `/` separator, not the platform's `FOLDER_SEPARATOR`, since it is
for use by Javascript, not by this platform's native C file-handling library.

=
void ResourceMap::write(filename *map_filename) {
	JSON_value *map = JSON::new_array();
	resource_map_entry *entry;
	LOOP_OVER(entry, resource_map_entry) {
		JSON_value *je = JSON::new_object();
		JSON::add_to_object(je, I"id", JSON::new_number(entry->resource_ID));
		TEMPORARY_TEXT(url)
		if (entry->is_picture) 
			WRITE_TO(url, "Figures/%S", Filenames::get_leafname(entry->currently_at));
		else
			WRITE_TO(url, "Sounds/%S", Filenames::get_leafname(entry->currently_at));
		JSON::add_to_object(je, I"url", JSON::new_string(url));
		DISCARD_TEXT(url)
		JSON::add_to_object(je, I"alttext", JSON::new_string(entry->alt_text));
		filename *F = entry->currently_at;
		text_stream *real_format = I"unknown";
		int format_found = 0;
		if (entry->is_picture) {
			unsigned int width = 0;
			unsigned int height = 0;
			FILE *FIGURE_FILE = Filenames::fopen(F, "rb");
			if (FIGURE_FILE) {
				real_format = I"JPEG";
				format_found = ImageFiles::get_JPEG_dimensions(FIGURE_FILE, &width, &height);
				fclose(FIGURE_FILE);
				if (format_found == 0) {
					FIGURE_FILE = Filenames::fopen(F, "rb");
					if (FIGURE_FILE) {
						real_format = I"PNG";
						format_found = ImageFiles::get_PNG_dimensions(FIGURE_FILE, &width, &height);
						fclose(FIGURE_FILE);
					}
				}
			}
			JSON::add_to_object(je, I"format", JSON::new_string(real_format));
			JSON::add_to_object(je, I"width", JSON::new_number((int) width));
			JSON::add_to_object(je, I"height", JSON::new_number((int) height));
		} else {
			unsigned int duration = 0, pBitsPerSecond = 0, pChannels = 0, pSampleRate = 0,
				midi_version = 0, no_tracks = 0;
			FILE *SOUND_FILE = Filenames::fopen(F, "rb");
			if (SOUND_FILE) {
				real_format = I"AIFF";
				format_found = SoundFiles::get_AIFF_duration(SOUND_FILE, &duration, &pBitsPerSecond,
					&pChannels, &pSampleRate);
				fclose(SOUND_FILE);
				if (format_found == 0) {
					SOUND_FILE = Filenames::fopen(F, "rb");
					if (SOUND_FILE) {
						real_format = I"Ogg Vorbis";
						format_found = SoundFiles::get_OggVorbis_duration(SOUND_FILE, &duration,
							&pBitsPerSecond, &pChannels, &pSampleRate);
						fclose(SOUND_FILE);
					}
				}
				if (format_found == 0) {
					SOUND_FILE = Filenames::fopen(F, "rb");
					if (SOUND_FILE) {
						real_format = I"MIDI";
						format_found = SoundFiles::get_MIDI_information(SOUND_FILE,
							&midi_version, &no_tracks);
						fclose(SOUND_FILE);
					}
				}				
				if (format_found == 0) real_format = I"unknown";
			}
			JSON::add_to_object(je, I"format", JSON::new_string(real_format));
			if (Str::eq(real_format, I"MIDI")) {
				JSON::add_to_object(je, I"version", JSON::new_number((int) midi_version));
				JSON::add_to_object(je, I"tracks", JSON::new_number((int) no_tracks));
			} else {
				JSON::add_to_object(je, I"duration", JSON::new_number((int) duration));
				JSON::add_to_object(je, I"bps", JSON::new_number((int) pBitsPerSecond));
				JSON::add_to_object(je, I"channels", JSON::new_number((int) pChannels));
				JSON::add_to_object(je, I"samplerate", JSON::new_number((int) pSampleRate));
			}
		}
		JSON::add_to_array(map, je);
	}
	text_stream RM_struct;
	text_stream *RM = &RM_struct;
	if (STREAM_OPEN_TO_FILE(RM, map_filename, UTF8_ENC) == FALSE)
		BlorbErrors::fatal_fs("can't open resource map for output", map_filename);
	JSON::encode(RM, map);
	STREAM_CLOSE(RM);
}
