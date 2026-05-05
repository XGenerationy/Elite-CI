.PHONY: verify ci-quick ci-full ci-ship ci-debt impact test-plan smart ship install-hooks ci-self-test ci-watch ci-flaky ci-all ci-fix ci-profile docs bats lint-ci

verify: ci-full

ci-quick:
	./ci/preflight.sh --mode quick

ci-full:
	./ci/preflight.sh --mode full

ci-ship:
	./ci/preflight.sh --mode ship

ci-debt:
	./ci/preflight.sh --mode debt

impact:
	./ci/impact.sh

test-plan:
	./ci/test-plan.sh

smart:
	./ci/test-plan.sh
	./ci/preflight.sh --mode full

ship:
ifndef MESSAGE
	@echo "Usage: make ship MESSAGE=\"your commit message\""
	@exit 1
endif
	./ci/ship.sh "$(MESSAGE)"

install-hooks:
	./ci/install-hooks.sh

ci-self-test:
	./ci/self-test.sh

ci-watch:
	@which fswatch >/dev/null 2>&1 || (echo "fswatch not installed. Run: brew install fswatch" && exit 1)
	@echo "Watching for changes... (Ctrl-C to stop)"
	@fswatch -o . | while read; do \
		echo "\n[$$(date +%H:%M:%S)] Change detected. Running quick gate..."; \
		./ci/preflight.sh --mode quick || true; \
	done

ci-flaky:
	./ci/checks/flaky.sh

ci-all:
	./ci/preflight.sh --mode full --all

ci-fix:
	./ci/preflight.sh --mode full --fix

ci-profile:
	./ci/preflight.sh --mode full --profile

docs:
	@mkdir -p docs
	@bash ci/scripts/gen-checks-doc.sh > docs/CHECKS.md 2>/dev/null || echo "# Checks\n\nSee ci/checks/manifest.yml" > docs/CHECKS.md
	@echo "Generated docs/CHECKS.md"

bats:
	bats ci/tests/

lint-ci:
	@for f in ci/*.sh ci/checks/*.sh ci/lib/*.sh ci/hook-dispatch.sh; do [ -f "$$f" ] && bash -n "$$f" && echo "OK: $$f"; done
