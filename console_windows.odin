package main

import win32 "core:sys/windows"

console_begin :: proc() {
	win32.SetConsoleCP(.UTF8)
	win32.SetConsoleOutputCP(.UTF8)
}
