PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin

pickcolor: main.swift
	swiftc -O -o $@ main.swift

build: pickcolor

install: pickcolor
	install -d $(BINDIR)
	install -m 755 pickcolor $(BINDIR)/pickcolor

clean:
	rm -f pickcolor

.PHONY: build install clean
