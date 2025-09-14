#load "utils.jai";
#load "csv.jai";

main :: () {
	args := get_command_line_arguments();
	if args.count < 2 return;


	region_timer("main");

	file := read_entire_file("temp\\words.txt");
	results := find_substring(file, args[1], temp);
	for < results {
		begin := it;
		end   := it;
		while begin > 0 {
			if file[begin] == #char "\n" {
				break;
			} else {
				begin -= 1;
			}
		}
		line := 0;
		while end < file.count {
			if file[end] == #char "\n" {
				line += 1;
				if line == 2 break;
			}
			end += 1;
		}
		print("---\n%\n\n", slice(file, begin, end-begin));
	}
}

Word :: struct {
	id : int;
	word : string;
	translation : string; // English
	fpos : int; // Position in index file.
}
words : [1024 * 100]Word;

#run {// preprocess
	dc : Build_Options_During_Compile;
	// dc.do_output = false;
	dc.output_executable_name = "rudy";
	set_build_options_dc(dc);
	words_txt, ok := read_entire_file("temp\\words.txt", log_errors=false);
	if !ok {
		process_raw_csv(true);
	} else {
		{
			region_timer("read processed words");
			words_txt, ok = read_entire_file("temp\\words.txt", log_errors=false);
			defer free(words_txt);
			if !ok {
				print("Failed to read temp\\words.txt");
				return;
			}

			for:string_by_line words_txt {
				word_id := it_index / 2;
				w := *words[word_id];
				w.id = word_id;
				idx := it_index % 2;
				if idx == {
					case 0;
						w.word = it;
					case 1;
						w.translation = it;
				}
			}
		}
		// for 10..20 {
		// 	print("word %: %\n", it, words[it]);
		// }
	}
}

process_raw_csv :: (save: bool) {
	load_csv :: (name: string) -> CsvData #expand {
		source := read_entire_file(tprint("data/%.csv", name));
		defer free(source);
		csv := csv_parse(source);
		`defer csv_free(*csv);
		return csv;
	}
	csv_words        := load_csv("words");
	csv_translations := load_csv("translations");

	max_word_id : int;
	for csv_words.rows {
		if it_index == 0 continue;
		if it.count < 1 continue;
		word_id, ok, _ := to_integer(it[0]);
		assert(ok, "Invalid word id string: %", it[0]);
		if !ok continue;
		if word_id > max_word_id max_word_id = word_id;
		words[word_id] = .{id = word_id, word = it[2]};
	}
	for csv_translations.rows {
		if it_index == 0 continue;
		if it.count < 1 continue;
		word_id, ok, _ := to_integer(it[2]);
		assert(ok, "Invalid word id string: %", it[2]);
		lang := it[1];
		translation := it[4];
		if lang != "en" continue;
		assert(word_id <= max_word_id, "Invalid word id %. Out of range.", word_id);
		words[word_id].translation = translation;
	}

	if save {
		make_directory_if_it_does_not_exist("temp");

		file := file_open("temp\\words.txt", true);
		for 0..max_word_id {
			word := words[it];
			file_write(*file, word.word);
			file_write(*file, "\n");
			file_write(*file, word.translation);
			file_write(*file, "\n");
		}
		file_close(*file);
		print("Processed temp\\words.txt saved.\n");
	}

	print("Read % rows.\nThe biggest word id: %.\n", csv_words.rows.count, max_word_id);
}

#import "File";
#import "Compiler";
