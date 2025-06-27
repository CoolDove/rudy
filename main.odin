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

main :: proc() {
	logger := log.create_console_logger()
	defer log.destroy_console_logger(logger)
	context.logger = logger

	pwd := os.get_current_directory(); defer delete(pwd)

	win32.SetConsoleCP(.UTF8)
	win32.SetConsoleOutputCP(.UTF8)

	translate()
}

translate :: proc() {
	word := "Я"

	if len(os.args) > 1 do word = os.args[1]

	url := fmt.aprintf("https://en.openrussian.org/ru/{}", word_encode(word)); defer delete(url)
	// fmt.printf("url: {}\n", url)

	state, exeout, exeerr, err := os2.process_exec({
		command = {"curl", url},
	}, context.allocator)

	defer {
		delete(exeout)
		delete(exeerr)
	}

	if err != nil {
		fmt.printf("exec err: {}\n", err)
		return;
	}

	os.write_entire_file("~cache.txt", exeout)

	source := string(exeout)
	point := strings.index(source, "class=\"section translations\"")
	if point < 0 {
		fmt.printf("[{}]\nno word\n", word)
		return
	}
	translation_part := source[point:math.max(point+1024, len(source))]

	fmt.printf("- {} -\n", word)
	if capture, ok := regex_match_scoped("<ul>(.*?)</ul>", translation_part); ok {
		remainstr := capture.groups[1]
		idx := 0
		for true {
			defer idx += 1
			if captureli, ok := regex_match_scoped("<li>(.*?)</li>", remainstr); ok {
				defer remainstr = remainstr[captureli.pos[0].y:]

				listr := captureli.groups[1]
				if capturetrans, ok := regex_match_scoped("class=\"content\".*<p class=\"tl\">(.*?)</p>", listr); ok {
					fmt.printf("{}. {}\n", idx+1, capturetrans.groups[1])
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
		fmt.printf("no word\n")
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
