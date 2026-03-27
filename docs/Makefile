MAN_DIR = ../man
MAN_PAGES = $(wildcard $(MAN_DIR)/*.1)
MD_FILES = $(notdir $(MAN_PAGES:.1=.md))
HTML_FILES = $(notdir $(MAN_PAGES:.1=.html))

# Default target generates everything
all: md html

# Generate Markdown using mandoc
md: $(MD_FILES)

%.md: $(MAN_DIR)/%.1
	mandoc -Tmarkdown $< > $@

# Generate HTML using mandoc
html: $(HTML_FILES)

%.html: $(MAN_DIR)/%.1
	mandoc -Thtml $< > $@

# Remove generated files
clean:
	rm -f *.md *.html

.PHONY: all md html clean