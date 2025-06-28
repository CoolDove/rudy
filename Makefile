SHELL = cmd
.SHELLFLAGS = /C
release:
	odin build . -o:speed -out:rudy.exe
	copy rudy.exe руд.exe /Y
debug:
	odin build . --debug
