.PHONY: serve build

serve:
	bundle exec jekyll serve --livereload

build:
	bundle exec jekyll build
