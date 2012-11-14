REPORTER = spec

test:
	@NODE_ENV=test ./node_modules/.bin/mocha \
		--reporter $(REPORTER) \
		--compilers coffee:coffee-script \
		--timeout 500

test-w:
	@NODE_ENV=test ./node_modules/.bin/mocha \
		--reporter $(REPORTER) \
		--compilers coffee:coffee-script \
		--timeout 500 \
		--growl \
		--watch

build:
	./node_modules/.bin/coffee \
		--compile \
		--output ./lib \
		./src
		
build-w:
	./node_modules/.bin/coffee \
		--compile \
		--watch \
		--output ./lib \
		./src

.PHONY: test test-w
