package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:io"
import "core:os/os2"
import "core:text/regex"
import "core:strings"
import "core:strconv"
import "core:path/filepath"
import "core:math"
import "core:unicode/utf8"
import "core:encoding/entity"
import "core:encoding/json"
import "core:encoding/csv"
import "core:encoding/base64"

import ansi "ansi_code"

Args :: struct {
	search, word : string,
	read : bool,
}
args : Args

@(deferred_out=csv.reader_destroy)
csv_reader_scoped :: proc(r: ^csv.Reader, source: string) -> ^csv.Reader {
	csv.reader_init_with_string(r, source)
	r.reuse_record = true
	r.reuse_record_buffer = true
	return r
}


DIR_PROG : string

PATH_WORDS : string
PATH_TRANSLATIONS : string
PATH_FORMS : string

main :: proc() {
	console_begin(); defer console_end()
	args_read(
		{argr_follow_by("-d"), arga_set(&args.word)},
		{argr_follow_by("-д"), arga_set(&args.word)}, // in case you're using cyrillic
		{argr_is("--read"),    arga_set(&args.read)},
		{argr_is("--читать"),  arga_set(&args.read)},
		{argr_any(),           arga_set(&args.search)}
	)


	prog_dir := filepath.dir(os.args[0]); defer delete(prog_dir)
	data_dir := filepath.join({ prog_dir, "data" }); defer delete(data_dir)
	DIR_PROG = prog_dir
	PATH_WORDS = filepath.join({ data_dir, "words.csv" })
	PATH_FORMS = filepath.join({ data_dir, "words_forms.csv" })
	PATH_TRANSLATIONS = filepath.join({ data_dir, "translations.csv" })

	if args.search != {} {// search
		buffer_tls := make([dynamic]string, 0, 8); defer delete(buffer_tls)
		word_ids := make(map[int]int); defer delete(word_ids)

		if is_cyrillic_rune(utf8.rune_at(args.search, 0)) {
			tbword := rg_search(fmt.tprintf("\\d+,.*?,{}.*?,", args.search), PATH_WORDS)
			defer delete(tbword)
			rsword : csv.Reader; csv_reader_scoped(&rsword, tbword)
			for record, idx in csv.iterator_next(&rsword) {
				word_id := strconv.atoi(record[0])
				if word_id in word_ids do word_ids[word_id] += 1
				else do word_ids[word_id] = 1
			}

			tbforms := rg_search(fmt.tprintf(",{}", args.search), PATH_FORMS)
			defer delete(tbforms)
			rsforms : csv.Reader; csv_reader_scoped(&rsforms, tbforms)
			for form_record, form_idx in csv.iterator_next(&rsforms) {
				word_id := strconv.atoi(form_record[1])
				if word_id in word_ids do word_ids[word_id] += 1
				else do word_ids[word_id] = 1
			}
		} else {
			tbtls := rg_search(fmt.tprintf("\\d+,en,.*\\b{}\\b", args.search), PATH_TRANSLATIONS)
			defer delete(tbtls)
			rstls : csv.Reader; csv_reader_scoped(&rstls, tbtls)
			if regx, regxerr := regex.create(args.search, {.Case_Insensitive}); regxerr == nil {
				defer regex.destroy_regex(regx)
				for tls_record, tls_idx in csv.iterator_next(&rstls) {
					capt, ok := regex.match(regx, tls_record[4])
					defer regex.destroy_capture(capt)
					if ok {
						word_id := strconv.atoi(tls_record[2])
						if word_id in word_ids do word_ids[word_id] += 1
						else do word_ids[word_id] = 1
					}
				}
			}
		}

		sb_search : strings.Builder
		strings.builder_init(&sb_search); defer strings.builder_destroy(&sb_search)

		wcount := len(word_ids)
		idx := 0
		for id, value in word_ids {
			defer idx += 1
			using strings
			write_string(&sb_search, "^")
			write_int(&sb_search, id)
			write_string(&sb_search, ",")
			if idx < (wcount-1) do write_rune(&sb_search, '|')
		}
		result := rg_search(strings.to_string(sb_search), PATH_WORDS)


		results_buffer : [5]string

		rsresult : csv.Reader; csv_reader_scoped(&rsresult, result)
		count : int
		for record, idx in csv.iterator_next(&rsresult) {
			tsl := rg_search(fmt.tprintf(",en,{},", strconv.atoi(record[0])), PATH_TRANSLATIONS)
			defer delete(tsl)
			if tsl == {} do continue

			clear(&buffer_tls)
			rstsl : csv.Reader; csv_reader_scoped(&rstsl, tsl)
			for tl_record, tl_idx in csv.iterator_next(&rstsl) {
				append(&buffer_tls, strings.clone(tl_record[4]))
			}
			defer {
				for t in buffer_tls do delete(t)
			}

			sb : strings.Builder
			strings.builder_init(&sb); defer strings.builder_destroy(&sb)
			c := strings.builder_len(sb)
			strings.write_string(&sb, record[2])
			results_buffer[count%5] = strings.to_string(sb)[c:]

			usage, _ := strings.replace_all(record[8], "\\n", "\n", context.temp_allocator)
			print_search_result(count%5+1, record[0], record[3], record[11], buffer_tls[:], usage)

			count += 1
			if (count>0 && count % 5 == 0) {
				ansi.color_ansi(.Gray)
				fmt.printf("- {} printed | press `Enter` to continue, other keys to break", count)
				ansi.color_ansi(.Default)
				fmt.print('\n')
				b, _ := io.read_byte(os.stream_from_handle(os.stdin), nil)
				if b > '0' && b < '6' {
					idx := b - '0'
					to_detail := results_buffer[idx-1]
					detail(to_detail)
					break
				} else if b == 13 {// `ENTER`
				} else {
					break
				}
				results_buffer = {}
			}
		}
	} else if (args.word != {}) {// detail
		detail(args.word)
	}
}


detail :: proc(word: string) {
	tbword := rg_search(fmt.tprintf("\\d+,\\d*,{}.*?,", word), PATH_WORDS)
	defer delete(tbword)
	rsword : csv.Reader; csv_reader_scoped(&rsword, tbword)
	word_id : int
	word_bare : string;
	for record, idx in csv.iterator_next(&rsword) {
		word_id = strconv.atoi(record[0])
		ansi.color(.Yellow)
		fmt.printf(" ⏺ ")
		print_accented(record[3])
		ansi.color(.Default)
		fmt.printf(" [{}]\n", record[11])
		word_bare = strings.clone(record[2])
		break
	}
	defer if word_bare != {} do delete(word_bare)
	tsl := rg_search(fmt.tprintf(",en,{},", word_id), PATH_TRANSLATIONS)
	defer delete(tsl)
	rstsl : csv.Reader; csv_reader_scoped(&rstsl, tsl)
	for tl_record, tl_idx in csv.iterator_next(&rstsl) {
		fmt.printf("\t▶ {}\n", tl_record[4])
		if tl_record[5] != {} do fmt.printf("Example:\n\t- {}\n\t- {}\n", tl_record[5], tl_record[6])
		if tl_record[7] != {} do fmt.printf("Info:\n\t{}\n", tl_record[7])
	}

	fmt.print("\n")

	forms := rg_search(fmt.tprintf("^\\d+,{},", word_id), PATH_FORMS)
	defer delete(forms)
	rsforms : csv.Reader; csv_reader_scoped(&rsforms, forms)
	for form_record, form_idx in csv.iterator_next(&rsforms) {
		ftype := form_record[2]
		fmt.printf(" - {}: ", ftype[3:])
		ansi.color(.Yellow)
		print_accented(form_record[4])
		ansi.color(.Default)
		fmt.print("\n")
	}

	// try to read
	if args.read {
		file_info := curl(fmt.tprintf("https://en.wiktionary.org/wiki/File:Ru-{}.ogg", word_bare))
		defer delete(file_info)
		file_url : string
		if capt, ok := regex_match_scoped("audio id=\"mwe_player.*?src=\"(.*?)\"", file_info); ok {
			file_url = fmt.aprintf("https:{}", capt.groups[1])
			when ODIN_DEBUG do fmt.printf("url: {}\n", file_url)
		} else {
			when ODIN_DEBUG do fmt.printf("failed to parse file info\n")
		}

		if file_url == {} do return
		defer delete(file_url)

		when ODIN_DEBUG do fmt.printf("download audio from: {}\n", file_url)
		audio :string= filepath.join({ DIR_PROG, fmt.tprintf("{}.ogg", word_bare) });
		curl_download(file_url, audio)
		if os.exists(audio) {
			defer os.remove(audio)
			state, exeout, exeerr, err := os2.process_exec({
				command = {"ffplay", "-nodisp", "-autoexit", audio},
			}, context.allocator)
			delete(exeout)
			delete(exeerr)
		} else {
			fmt.printf("failed to download audio file")
		}
	}
}


is_cyrillic_rune :: proc(r: rune) -> bool {
	return (r >= 0x0400 && r <= 0x04FF) ||
		(r >= 0x0500 && r <= 0x052F) ||
		(r >= 0x2DE0 && r <= 0x2DFF) ||
		(r >= 0xA640 && r <= 0xA69F) ||
		(r >= 0x1C80 && r <= 0x1C8F)
}

print_search_result :: proc(idx: int, id: string, accented, type: string, tls: []string, usage: string={}) {
	ansi.color(.Yellow)
	fmt.printf(" {}⏺ ", idx)
	print_accented(accented)
	fmt.print(' ')
	ansi.color(.Default)
when ODIN_DEBUG {
	fmt.printf(" {} ", id)
}
	fmt.printf("[{}]\n", type)

	for tl in tls do fmt.printf("\t▶ {}\n", tl)

	if usage != {} {
		fmt.printf("  Usage:\n")
		// usage, _ = strings.replace_all(usage, "\\n", "\n", context.temp_allocator)
		usage := usage
		for line in strings.split_lines_iterator(&usage) {
			fmt.printf("\t{}\n", line)
		}
	}
	fmt.print("\n")
}

rg_search :: proc(pattern, file: string, ignore_case:= true, allocator:= context.allocator) -> string {
	context.allocator = allocator
	state, exeout, exeerr, err := os2.process_exec({
		command = {"rg", pattern, file,
			"--no-heading",
			"--no-line-number",
			"--color=never",
			"--ignore-case" if ignore_case else "--case-sensitive"
		},
	}, context.allocator)
	delete(exeerr)
	return string(exeout)
}

curl :: proc(url: string) -> string {
	state, exeout, exeerr, err := os2.process_exec({
		command = {"curl", "--ssl-no-revoke", url},
	}, context.allocator)
	delete(exeerr)
	return string(exeout)
}
curl_download :: proc(url: string, file: string) {
	state, exeout, exeerr, err := os2.process_exec({
		command = {"curl", "--ssl-no-revoke", url, "-o", file},
	}, context.allocator)
	delete(exeout)
	delete(exeerr)
}

print_accented :: proc(word: string) {
	for r in word {
		if r == '\'' do fmt.print('\u0301')
		else do fmt.print(r)
	}
}

@(deferred_out=_destroy_capture)
regex_match_scoped :: proc(pattern, source: string) -> (capture: regex.Capture, ok: bool) {
	regexp, err := regex.create(pattern); defer if err!=nil {regex.destroy_regex(regexp)}
	if err == nil {
		return regex.match(regexp, source)
	} else {
		return {}, false
	}
}
@(private="file")
_destroy_capture :: proc(c: regex.Capture, ok: bool) {
	regex.destroy_capture(c)
}

@(private="file")
word_encode :: proc(word: string, allocator:= context.temp_allocator) -> string {
	context.allocator = allocator
	using strings
	sb : Builder
	builder_init_len_cap(&sb, 0, 128)
	wordb := transmute([]u8)word
	for b in wordb {
		write_rune(&sb, '%')
		write_string(&sb, fmt.tprintf("%X", int(b)))
	}
	return to_string(sb)
}

string_sub_after :: proc(source, substr: string) -> string {// including the matched part
	index := strings.index(source, substr)
	if index == -1 do return {}
	return source[index:]
}
string_sub_before :: proc(source, substr: string, include:= false) -> string {// excluding the matched part
	index := strings.index(source, substr)
	if index == -1 do return {}
	return source[:index + (len(substr) if include else 0)]
}
