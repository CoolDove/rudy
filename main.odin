package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:os/os2"
import "core:text/regex"
import "core:strings"
import "core:strconv"
import "core:math"
import "core:encoding/entity"
import "core:encoding/json"
import "core:encoding/base64"

import ansi "ansi_code"

Args :: struct {
	search, word : string,
}
args : Args

main :: proc() {
	logger := log.create_console_logger()
	defer log.destroy_console_logger(logger)
	context.logger = logger
	pwd := os.get_current_directory(); defer delete(pwd)

	console_begin()
	args_read(
		{argr_follow_by("-d"), arga_set(&args.word)},
		{argr_follow_by("-д"), arga_set(&args.word)}, // in case you're using cyrillic
		{argr_any(), arga_set(&args.search)}
	)

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
	if cap_sec_trls, ok := regex_match_scoped("<div class=\"section translations\">(.*?)<div class=\"section", source); ok {
		section_trls = cap_sec_trls.groups[1]
	} else do return false

	if capture, ok := regex_match_scoped("<ul>(.*?)</ul>", section_trls); ok {
		ite_trls, err := regex.create_iterator(capture.groups[1], "<li>.*?<div class=\"content\">(.*?)</div></li>")
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
				} else if type == "tl-also" do fmt.printf("\tAlso: {}\n", text)
				else do fmt.printf("\t{}\n", text)
			}
			fmt.print("---\n")
		}
	}

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
