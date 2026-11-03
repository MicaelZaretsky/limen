# limen: make doc | examples | test | print-test | gallery | web | svg | install | uninstall | dist | ctan | clean
VERSION  := 0.2
FILES    := limen.sty limen.lua limen-art.lua limen-pdf.lua limen-palettes.lua limen-svg.lua
BUILD    := build
LUALATEX := lualatex -interaction=nonstopmode -halt-on-error
EXAMPLES := $(basename $(notdir $(wildcard examples/*.tex)))
TEXMFHOME = $(shell kpsewhich -var-value TEXMFHOME)

# the package is found from any directory of the project
export TEXINPUTS := $(CURDIR):$(TEXINPUTS)
export LUAINPUTS := $(CURDIR):$(LUAINPUTS)

.PHONY: all doc examples test print-test gallery web svg install uninstall dist ctan clean

all: doc examples

doc: $(BUILD)/limen-guide.pdf $(BUILD)/limen-guide-en.pdf

$(BUILD)/limen-guide.pdf $(BUILD)/limen-guide-en.pdf: $(BUILD)/%.pdf: doc/%.tex doc/limen-guide-common.tex $(FILES) | $(BUILD)
	cd doc && $(LUALATEX) -output-directory=../$(BUILD) $*.tex >/dev/null
	cd doc && $(LUALATEX) -output-directory=../$(BUILD) $*.tex >/dev/null
	cd doc && $(LUALATEX) -output-directory=../$(BUILD) $*.tex | tail -2

examples: $(EXAMPLES:%=$(BUILD)/%.pdf)

$(BUILD)/%.pdf: examples/%.tex $(FILES) | $(BUILD)
	cd examples && $(LUALATEX) -output-directory=../$(BUILD) $*.tex >/dev/null
	cd examples && $(LUALATEX) -output-directory=../$(BUILD) $*.tex | tail -2

test:
	python3 tests/run.py

# one A4 sheet for checking a printer
print-test: | $(BUILD)
	cd tools && $(LUALATEX) -output-directory=../$(BUILD) print-test.tex | tail -2
	cp $(BUILD)/print-test.pdf doc/limen-print-test.pdf

gallery:
	python3 tools/gallery.py
	python3 tools/animate.py

web:
	python3 web/build.py

# one page without TeX; other options: texlua limen-svg.lua --help
svg:
	texlua limen-svg.lua --page 3 --pages 8 > $(BUILD)/page-3.svg

install:
	install -d "$(TEXMFHOME)/tex/lualatex/limen"
	install -m 644 $(FILES) "$(TEXMFHOME)/tex/lualatex/limen"
	@echo "installed into $(TEXMFHOME)/tex/lualatex/limen"

uninstall:
	rm -f $(addprefix "$(TEXMFHOME)/tex/lualatex/limen/,$(addsuffix ",$(FILES)))
	-rmdir "$(TEXMFHOME)/tex/lualatex/limen"

dist:
	cd .. && rm -f limen-$(VERSION).zip && zip -q -r limen-$(VERSION).zip $(notdir $(CURDIR)) -x '*/build/*' '*/.git/*' '*.aux' '*.log' '*.toc' '*.out' '*/typst/limen-art/*' '*/typst/example.pdf' '*/web/fragment.html' '*/limen-ctan.zip'
	@echo "../limen-$(VERSION).zip"

# the package for CTAN: build/distrib/limen-ctan.zip
ctan:
	l3build ctan

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
