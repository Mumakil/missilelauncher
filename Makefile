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

.PHONY: test test-w
