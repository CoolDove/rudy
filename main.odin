package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:os/os2"
import "core:text/regex"
import "core:strings"
import "core:strconv"
import "core:math"
import "core:encoding/json"
import "core:encoding/base64"

import "ohtml"


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
		{argr_follow_by("-s"), arga_set(&args.search)},
		{argr_any(), arga_set(&args.word)}
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

	section_basics := string_sub_after(source, "<div class=\"section basics\"")
	section_basics = string_sub_before(section_basics, "<div class=\"section translations")

	if section_basics != {} {
		fmt.printf("- {} -\n", word)
		if capoverview, ok := regex_match_scoped("class=\"overview\">(.*?)</div>", section_basics); ok {
			it, _ := regex.create_iterator(capoverview.groups[1], "<p>(.*?)</p>")
			for capture, idx in regex.match_iterator(&it) {
				line := capture.groups[1]
				if strings.starts_with(line, "<a") do continue
				fmt.printf("\t{}\n", line)
			}
		}
	} else do return false

	fmt.print("\n")
	section_translations := string_sub_after(source, "<div class=\"section translations\"")
	section_translations = string_sub_before(section_translations, "<div class=\"section sentences")

	if capture, ok := regex_match_scoped("<ul>(.*?)</ul>", section_translations); ok {
		remainstr := capture.groups[1]
		idx := 0
		for true {
			defer idx += 1
			if captureli, ok := regex_match_scoped("<li>(.*?)</li>", remainstr); ok {
				defer remainstr = remainstr[captureli.pos[0].y:]

				listr := captureli.groups[1]
				if capturetrans, ok := regex_match_scoped("class=\"content\".*<p class=\"tl\">(.*?)</p>", listr); ok {
					fmt.printf(" {}. {}\n", idx+1, capturetrans.groups[1])
					if also, ok := regex_match_scoped("class=\"tl-also\">(.*?)</p>", listr); ok {
						if alsostr, ok2 := regex_match_scoped("(\\w+)<.*?:.*?-->(.*)", also.groups[1]); ok2 {
							fmt.printf("\t{}: {}\n", alsostr.groups[1], alsostr.groups[2])
						}
					}
				}
				fmt.print("\n")
			} else {
				break
			}
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
		fmt.printf(" {}. {} [{}]\n", idx+1, jword["ru"], jword["type"])
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
ohtml_format :: proc(e: ^ohtml.Element, depth:= 0) {
	for i in 0..<depth do fmt.print(' ')
	fmt.printf("[{}]. : {}\n", e.type, e.text)
	for c in e.children {
		ohtml_format(c, depth+1)
	}
	for i in 0..<depth do fmt.print(' ')
	fmt.printf("[/{}].", e.type)
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
