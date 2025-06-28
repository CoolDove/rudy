package main

import "core:fmt"
import "core:log"
import "core:os"
import "core:os/os2"
import "core:text/regex"
import "core:strings"
import "core:strconv"
import "core:math"
import "core:encoding/base64"
import win32 "core:sys/windows"

import "ohtml"

main :: proc() {
	logger := log.create_console_logger()
	defer log.destroy_console_logger(logger)
	context.logger = logger

	pwd := os.get_current_directory(); defer delete(pwd)

	win32.SetConsoleCP(.UTF8)
	win32.SetConsoleOutputCP(.UTF8)


	word := "Я"
	if len(os.args) > 1 do word = os.args[1]

	if !translate(word) {
		search(word)
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

	fmt.printf("- {} -\n", word)

	// point_basics := strings.index(source, "class=\"section basics\"")

	section_basics := string_sub_after(source, "<div class=\"section basics\"")
	section_basics = string_sub_before(section_basics, "<div class=\"section translations")

	// fmt.printf("block: {}\n", section_basics)
	if section_basics != {} {
		if capoverview, ok := regex_match_scoped("class=\"overview\">(.*?)</div>", section_basics); ok {
			it, _ := regex.create_iterator(capoverview.groups[1], "<p>(.*?)</p>")
			for capture, idx in regex.match_iterator(&it) {
				line := capture.groups[1]
				if strings.starts_with(line, "<a") do continue
				fmt.printf("\t{}\n", line)
			}
		}
	}

	fmt.print("\n")
	point := strings.index(source, "class=\"section translations\"")
	if point < 0 {
		return false
	}
	translation_part := source[point:math.max(point+1024, len(source))]

	if capture, ok := regex_match_scoped("<ul>(.*?)</ul>", translation_part); ok {
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
	} else {
		return false
	}
	return true
}


search :: proc(word: string) -> bool {
	url := fmt.aprintf("https://en.openrussian.org?search={}", word_encode(word)); defer delete(url)

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

	point_basics := strings.index(source, "<div class=\"search-results\"")
	if point_basics >= 0 {
		section_basics := source[point_basics:math.max(point_basics+1024, len(source))]
		fmt.printf("section: {}\n", section_basics)
		elem := ohtml.parse(section_basics)
		ohtml_format(elem)
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
string_sub_before :: proc(source, substr: string) -> string {// excluding the matched part
	index := strings.index(source, substr)
	if index == -1 do return {}
	return source[:index]
}
