package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:io"
import "core:os/os2"
import "core:text/regex"
import "core:strings"
import "core:strconv"
import "core:math"
import "core:encoding/entity"
import "core:encoding/json"
import "core:encoding/csv"
import "core:encoding/base64"

import ansi "ansi_code"

Args :: struct {
	search, word : string,
}
args : Args

@(deferred_out=csv.reader_destroy)
csv_reader_scoped :: proc(r: ^csv.Reader, source: string) -> ^csv.Reader {
	csv.reader_init_with_string(r, source)
	r.reuse_record = true
	r.reuse_record_buffer = true
	return r
}

main :: proc() {
	console_begin(); defer console_end()
	args_read(
		{argr_follow_by("-d"), arga_set(&args.word)},
		{argr_follow_by("-д"), arga_set(&args.word)}, // in case you're using cyrillic
		{argr_any(), arga_set(&args.search)}
	)

	buffer_tls := make([dynamic]string, 0, 8); defer delete(buffer_tls)

	if args.search != {} {
		word_ids := make(map[int]int); defer delete(word_ids)

		tbword := rg_search(fmt.tprintf("\\d+,.*?,{}.*?,", args.search),  "data\\words.csv")
		defer delete(tbword)
		rsword : csv.Reader; csv_reader_scoped(&rsword, tbword)
		for record, idx in csv.iterator_next(&rsword) {
			word_id := strconv.atoi(record[0])
			if word_id in word_ids do word_ids[word_id] += 1
			else do word_ids[word_id] = 1
		}

		tbforms := rg_search(fmt.tprintf("^.*{}.*?,", args.search), "data\\words_forms.csv")
		defer delete(tbforms)
		rsforms : csv.Reader; csv_reader_scoped(&rsforms, tbforms)
		for form_record, form_idx in csv.iterator_next(&rsforms) {
			word_id := strconv.atoi(form_record[1])
			if word_id in word_ids do word_ids[word_id] += 1
			else do word_ids[word_id] = 1
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
		result := rg_search(strings.to_string(sb_search), "data\\words.csv")

		rsresult : csv.Reader; csv_reader_scoped(&rsresult, result)
		for record, idx in csv.iterator_next(&rsresult) {
			tsl := rg_search(fmt.tprintf(",en,{},", strconv.atoi(record[0])), "data\\translations.csv")
			defer delete(tsl)
			if tsl == {} do continue

			clear(&buffer_tls)
			rstsl : csv.Reader; csv_reader_scoped(&rstsl, tsl)
			for tl_record, tl_idx in csv.iterator_next(&rstsl) {
				for tl in strings.split_iterator(&tl_record[4], ", ") {
					append(&buffer_tls, tl)
				}
			}

			usage, _ := strings.replace_all(record[8], "\\n", "\n", context.temp_allocator)
			print_result(record[3], record[11], buffer_tls[:], usage)
		}
	}
}

print_result :: proc(accented, type: string, tls: []string, usage: string={}) {
	ansi.color(.Yellow)
	fmt.print(" ⏺ ")
	print_accented(accented)
	fmt.print(' ')
	ansi.color(.Default)
	fmt.printf("[{}]\n", type)

	for tl in tls do fmt.printf("\t▶ {}\n", tl)

	if usage != {} {
		fmt.printf("  Usage:\n")
		// usage, _ = strings.replace_all(usage, "\\n", "\n", context.temp_allocator)
		usage := usage
		for line in strings.split_lines_iterator(&usage) {
			fmt.printf("\t{}\n", line)
		}
	} else {
		fmt.print("\n")
	}
}

rg_search :: proc(pattern, file: string, allocator:= context.allocator) -> string {
	context.allocator = allocator
	state, exeout, exeerr, err := os2.process_exec({
		command = {"rg", pattern, file,
			"--no-heading",
			"--no-line-number",
			"--color=never",
		},
	}, context.allocator)
	delete(exeerr)
	return string(exeout)
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
