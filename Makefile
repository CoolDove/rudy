SHELL = cmd
.SHELLFLAGS = /C
release:
	chcp 65001
	odin build . -o:speed -out:rudy.exe
	copy rudy.exe руд.exe /Y
debug:
	odin build . --debug
