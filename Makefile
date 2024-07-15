.PHONY: docs
docs:
	@rm -rf docs/* && \
	jsonnet -S -m docs/ -J . -J vendor --exec "(import 'doc-util/main.libsonnet').render(import 'main.libsonnet')"

.PHONY: test
test:
	@jsonnet -J . -J vendor test/main.jsonnet
