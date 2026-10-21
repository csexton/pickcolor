PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
ACTION = build/PickColor.lbaction

pickcolor: main.swift
	swiftc -O -o $@ main.swift

build: pickcolor

install: pickcolor
	install -d $(BINDIR)
	install -m 755 pickcolor $(BINDIR)/pickcolor

# Build a self-contained LaunchBar action (the binary lives inside the bundle)
# and hand it to LaunchBar, which asks to install or update it.
launchbar: pickcolor launchbar/Info.plist launchbar/default.sh launchbar/iconTemplate.pdf
	rm -rf $(ACTION)
	install -d $(ACTION)/Contents/Scripts $(ACTION)/Contents/Resources
	install -m 644 launchbar/Info.plist $(ACTION)/Contents/Info.plist
	install -m 644 launchbar/iconTemplate.pdf $(ACTION)/Contents/Resources/iconTemplate.pdf
	install -m 755 launchbar/default.sh $(ACTION)/Contents/Scripts/default.sh
	install -m 755 pickcolor $(ACTION)/Contents/Scripts/pickcolor
	open -a LaunchBar $(ACTION)

clean:
	rm -rf pickcolor build

.PHONY: build install launchbar clean
