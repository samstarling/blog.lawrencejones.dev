.PHONY: serve build _sass/fonts/_text.scss font-urls

serve:
	bundle exec jekyll serve --livereload

build:
	bundle exec jekyll build

FONT_FAMILY=$(shell ruby -r yaml -r json -e "puts YAML.load_file('_config.yml').dig('theme_settings', 'google_fonts')")

# Vendor this file so we can avoid a chained network request to fetch it
_sass/fonts/_text.scss:
	@curl --silent https://fonts.googleapis.com/css?family=$(FONT_FAMILY) > $@

# Use these URLs in the _includes/head.html to preload the font files
font-urls:
	@cat _sass/external/_text.scss | perl -wnl -e '/(https.+?.ttf)/ and print $$1'
