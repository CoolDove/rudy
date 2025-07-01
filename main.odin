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

options : [dynamic]string

@(deferred_out=csv.reader_destroy)
csv_reader_scoped :: proc(r: ^csv.Reader, source: string) -> ^csv.Reader {
	csv.reader_init_with_string(r, source)
	r.reuse_record = true
	r.reuse_record_buffer = true
	return r
}

Word :: struct {
	bare, accented : string,
}


WordType :: enum {
	Noun, Verb, Adjv, Other
}

WordRecord :: struct {
	word : Word,
	type : WordType,
	using forms : struct #raw_union {
		using verb : WordFormVerb,
		using noun : WordFormNoun,
		using adjv : WordFormAdjv,
	}
}

WordFormVerb :: struct {// 
	gerund_present, gerund_past : Word,

	presfut_sg1, presfut_sg2, presfut_sg3 : Word,
	presfut_pl1, presfut_pl2, presfut_pl3 : Word,

	past_m, past_f, past_n, past_pl : Word,

	imperative_sg, imperative_pl : Word,

	participle_active_present : Word,
	participle_active_past : Word,

	participle_passive_present : Word,
	participle_passive_past : Word
}

WordFormNoun :: struct {
	sg_nom, sg_gen, sg_dat, sg_acc, sg_inst, sg_prep : Word,
	pl_nom, pl_gen, pl_dat, pl_acc, pl_inst, pl_prep : Word,
}

WordFormAdjv :: struct {
	m_nom, m_gen, m_dat, m_acc, m_inst, m_prep : Word,
	f_nom, f_gen, f_dat, f_acc, f_inst, f_prep : Word,
	n_nom, n_gen, n_dat, n_acc, n_inst, n_prep : Word,

	short_m, short_f, short_n, short_pl : Word,

	comparative : Word,
	superlative : Word,
}

main :: proc() {
	console_begin(); defer console_end()
	args_read(
		{argr_follow_by("-d"), arga_set(&args.word)},
		{argr_follow_by("-д"), arga_set(&args.word)}, // in case you're using cyrillic
		{argr_any(), arga_set(&args.search)}
	)

	if args.search != {} {
		rwords, rtls, rforms : csv.Reader
		csv_reader_scoped(&rwords, #load("./data/words.csv"))
		csv_reader_scoped(&rtls,   #load("./data/translations.csv"))
		csv_reader_scoped(&rforms, #load("./data/words_forms.csv"))

		words := make([]WordRecord, 200_000)
		for record, idx in csv.iterator_next(&rwords) {
			id := strconv.atoi(record[0])
			w : WordRecord
			w.word.bare = strings.clone(record[2])
			w.word.accented = strings.clone(record[3])
			switch record[11] {
			case "noun": w.type = .Noun
			case "verb": w.type = .Verb
			case "adjective": w.type = .Adjv
			case "other": w.type = .Other
			}

			words[id] = w
		}

		for record, idx in csv.iterator_next(&rwords) {
			form := record[2]
			wordr := &words[strconv.atoi(record[1])]

			word :Word= {strings.clone(record[4]), strings.clone(record[5])}

			switch form {
			case "ru_verb_gerund_present":
				wordr.gerund_present = word
			case "ru_verb_gerund_past":
				wordr.gerund_past = word
			case "ru_verb_presfut_sg1":
				wordr.presfut_sg1 = word
			case "ru_verb_presfut_sg2":
				wordr.presfut_sg2 = word
			case "ru_verb_presfut_sg3":
				wordr.presfut_sg3 = word
			case "ru_verb_presfut_pl1":
				wordr.presfut_pl1 = word
			case "ru_verb_presfut_pl2":
				wordr.presfut_pl2 = word
			case "ru_verb_presfut_pl3":
				wordr.presfut_pl3 = word

			case "ru_verb_past_m":
				wordr.past_m = word
			case "ru_verb_past_f":
				wordr.past_f = word
			case "ru_verb_past_n":
				wordr.past_n = word
			case "ru_verb_past_pl":
				wordr.past_pl = word

			case "ru_verb_imperative_sg":
				wordr.imperative_sg = word
			case "ru_verb_imperative_pl":
				wordr.imperative_pl = word

			case "ru_verb_participle_active_present":
				wordr.participle_active_present = word
			case "ru_verb_participle_active_past":
				wordr.participle_active_past = word

			case "ru_verb_participle_passive_present":
				wordr.participle_passive_present = word
			case "ru_verb_participle_passive_past":
				wordr.participle_passive_past = word
			}
		}

		for w in words {
			if w.word != {} do continue
			fmt.printf("word: {}: {}\n", w.word.bare, w.verb)
		}
	}
}

old_main :: proc() {
	logger := log.create_console_logger()
	defer log.destroy_console_logger(logger)
	context.logger = logger
	pwd := os.get_current_directory(); defer delete(pwd)

	console_begin(); defer console_end()
	args_read(
		{argr_follow_by("-d"), arga_set(&args.word)},
		{argr_follow_by("-д"), arga_set(&args.word)}, // in case you're using cyrillic
		{argr_any(), arga_set(&args.search)}
	)

	options = make([dynamic]string); defer delete(options)

	if args.search != {} {
		if !search(args.search) {
			fmt.printf("no match")
		}
	} else if args.word != {} {
		if !translate(args.word) {
			fmt.printf("no word")
		}
	} else {
		fmt.print("bad args\n")
	}
}

translate :: proc(word: string) -> bool {
	url := fmt.aprintf("https://en.openrussian.org/ru/{}", word_encode(word)); defer delete(url)

	state, exeout, exeerr, err := os2.process_exec({
		command = {"curl", url},
	}, context.allocator)

	defer {
		delete(exeout)
		delete(exeerr)
	}

	if err != nil {
		fmt.printf("exec err: {}\n", err)
		return false;
	}

	os.write_entire_file("~cache.txt", exeout)
	source := string(exeout)
	source = string_sub_after(source, "<main")
	source = string_sub_before(source, "</main>", true)

	section_basics : string
	if cap_sec_basics, ok := regex_match_scoped("<div class=\"section basics\">(.*?)<div class=\"section", source); ok {
		section_basics = cap_sec_basics.groups[1]
	} else do return false

	if section_basics != {} {
		ansi.color_ansi(.Yellow)
		if capword, ok := regex_match_scoped("class=\"bare.*?<span>(.*?)</span>", section_basics); ok {
			fmt.printf("  {} \n", capword.groups[1])
		} else {
			fmt.printf("  {} \n", word)
		}
		ansi.color_ansi(.Default)
		if capoverview, ok := regex_match_scoped("class=\"overview\">(.*?)</div>", section_basics); ok {
			it, _ := regex.create_iterator(capoverview.groups[1], "<p>(.*?)</p>")
			for capture, idx in regex.match_iterator(&it) {
				line := capture.groups[1]
				if strings.contains(line, "</a>") do continue
				fmt.printf("\t{}\n", line)
			}
		}
	} else do return false

	fmt.print("---\n")

	section_trls : string
	if cap_sec_trls, ok := regex_match_scoped("<div class=\"section translations\">.*?<ul>(.*?)</ul>.*?<div class=\"section", source); ok {
		section_trls = cap_sec_trls.groups[1]
		ite_trls, err := regex.create_iterator(section_trls, "<li>.*?<div class=\"content\">(.*?)</div></li>")
		trl_idx := 0
		for trls, trls_idx in regex.match_iterator(&ite_trls) {
			defer trl_idx += 1
			ite_trlc, err := regex.create_iterator(trls.groups[1], "<p class=\"(.*?)\">(.*?)</p>")
			for it, idx in regex.match_iterator(&ite_trlc) {
				type := it.groups[1]
				text := it.groups[2]
				text, _ = entity.decode_xml(text, allocator=context.temp_allocator)
				text, _ = strings.replace_all(text, "<!-- -->", "", context.temp_allocator)
				if type == "tl" {
					ansi.color_ansi(.Cyan)
					fmt.printf(" {}. {}\n", trl_idx+1, text)
					ansi.color_ansi(.Default)
				} else do fmt.printf("\t{}\n", text)
			}
			fmt.print("---\n")
		}
	} else do return false


	fmt.printf("URL: {}\n", url)

	return true
}

search :: proc(word: string) -> bool {
	url := fmt.aprintf("https://api.openrussian.org/suggestions?q={}&dummy=1751091002996&lang=en", word); defer delete(url)

	state, exeout, exeerr, err := os2.process_exec({
		command = {"curl", url},
	}, context.allocator)

	defer {
		delete(exeout)
		delete(exeerr)
	}

	if err != nil {
		fmt.printf("exec err: {}\n", err)
		return false;
	}

	os.write_entire_file("~cache.txt", exeout)
	source := string(exeout)

	jroot, jerr := json.parse(exeout)

	if jerr != nil {
		fmt.printf("failed to parse json: {}\n", jerr)
		return false
	}

	jmatch := jroot.(json.Object)["result"].(json.Object)["words"]
	idx : int
	if _, isnil := jmatch.(json.Null); isnil do return false
	for match in jmatch.(json.Array) {
		defer idx += 1
		jword := match.(json.Object)["word"].(json.Object)
		fmt.printf(" {}. ", idx+1)
		ansi.color_ansi(.Yellow)
		word_stressed, _ := strings.replace_all(jword["ru"].(json.String), "\'", "\u0301")

		word_plain, _ := strings.remove_all(jword["ru"].(json.String), "\'", context.temp_allocator)
		append(&options, word_plain)

		fmt.print(word_stressed)
		ansi.color_ansi(.Default)
		fmt.printf(" [{}]\n", jword["type"])

		tls := jword["tls"].(json.Array)
		for tl in tls {
			fmt.printf("\t‣ ")
			for tlp, idx in tl.(json.Array) {
				fmt.print(tlp.(json.String))
				if idx == len(tl.(json.Array))-1 do fmt.print("\n")
				else do fmt.print(", ")
			}
		}
	}

	if len(options) > 0 {
		in_stream := os.stream_from_handle(os.stdin)
		ch, sz, err := io.read_rune(in_stream)
		if ch > '0' && ch <= '9' {
			idx := cast(int)(ch - '0')
			idx -= 1
			if idx < len(options) {
				fmt.printf("detail {} - {}\n\n", ch, options[idx])
				translate(options[idx])
			}
		}
	}

	return true
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
