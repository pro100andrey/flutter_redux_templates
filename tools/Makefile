# frx — install & build helpers.
#
# The two things worth automating: `dart install` for the CLI, and the
# compile → package → install-into-the-right-profile loop for the extension.
# The profile matters: VSCode installs extensions per profile, so a VSIX put in
# the Default profile is invisible while you work in, say, "Flutter".
#
#   make                     what you can run
#   make profiles            which profiles exist, and where frx is installed
#   make install PROFILE=Flutter
#
# Set PROFILE once in your shell (`export PROFILE=Flutter`) and forget it.

SHELL := /bin/bash
CODE  ?= code

# Empty PROFILE means VSCode's Default profile — which is very likely NOT where
# you are working, hence the warning in `ext-install`.
PROFILE ?=
PROFILE_ARG := $(if $(PROFILE),--profile "$(PROFILE)",)

EXT_DIR     := vscode
EXT_VERSION := $(shell node -p "require('./$(EXT_DIR)/package.json').version" 2>/dev/null)
VSIX        := frx-$(EXT_VERSION).vsix

.DEFAULT_GOAL := help
.PHONY: help install cli ext package ext-install profiles check test docs skills contract template uninstall clean

help:
	@echo "frx — CLI $(shell sed -n 's/^version: //p' pubspec.yaml | head -1) · extension $(EXT_VERSION)"
	@echo
	@echo "  make install [PROFILE=<name>]   CLI + extension (the everyday one)"
	@echo "  make cli                        dart install the frx binary onto PATH"
	@echo "  make ext     [PROFILE=<name>]   compile, package and install the extension"
	@echo "  make package                    build the VSIX only"
	@echo "  make profiles                   list VSCode profiles + the frx build in each"
	@echo
	@echo "  make check                      everything CI runs, locally"
	@echo "  make test                       dart test + the extension suite"
	@echo "  make docs                       regenerate docs/flows"
	@echo "  make skills                     regenerate .claude/skills from the commands"
	@echo "  make contract                   regenerate the extension's constants from the CLI"
	@echo "  make template                   repack the template 'frx create' unpacks"
	@echo "  make uninstall [PROFILE=<name>] remove both"
	@echo "  make clean                      drop build output"
	@echo
	@echo "PROFILE is currently: $(if $(PROFILE),$(PROFILE),<unset — VSCode's Default profile>)"

install: cli ext

# --- CLI ---------------------------------------------------------------------

# `dart install <dir>` — the descriptor forms in `dart install --help` are for
# hosted/git packages; a local checkout installs by path.
cli:
	dart pub get
	dart install .
	@frx --version >/dev/null 2>&1 && echo "✓ $$(frx --version) on PATH" || echo "⚠ installed, but frx is not on PATH — add ~/Library/Application Support/Dart/install/bin (macOS) or ~/.dart/install/bin"

# --- extension ---------------------------------------------------------------

package:
	cd $(EXT_DIR) && npm install --silent && npm run compile && npx --yes @vscode/vsce package
	@echo "✓ $(EXT_DIR)/$(VSIX)"

ext: package ext-install

# `--force` because the version rarely changes between local builds, and without
# it VSCode declines to reinstall the same version.
ext-install:
	@$(if $(PROFILE),scripts/vscode-profiles.sh --names | grep -qxF "$(PROFILE)" || { echo "No VSCode profile named \"$(PROFILE)\". Known:"; scripts/vscode-profiles.sh --names | sed 's/^/  /'; exit 1; },true)
	@test -f "$(EXT_DIR)/$(VSIX)" || { echo "missing $(EXT_DIR)/$(VSIX) — run 'make package'"; exit 1; }
	@$(if $(PROFILE),,echo "⚠ PROFILE is unset — installing into VSCode's Default profile. 'make profiles' shows the others.")
	cd $(EXT_DIR) && $(CODE) $(PROFILE_ARG) --install-extension "$(VSIX)" --force
	@echo "✓ installed into $(if $(PROFILE),profile \"$(PROFILE)\",the Default profile) — now run 'Developer: Reload Window'"

profiles:
	@scripts/vscode-profiles.sh

# --- checks ------------------------------------------------------------------

check:
	dart format --output=none --set-exit-if-changed lib test bin
	dart analyze
	dart test
	cd $(EXT_DIR) && npm install --silent && npm run typecheck && npm run validate && npm test

test:
	dart test
	cd $(EXT_DIR) && npm test

docs:
	dart run bin/frx.dart flow --md --root ..

# The agent skills in ../.claude/skills — one per command plus the router,
# derived from the command objects themselves so the flag lists cannot drift
# from the CLI. `make check` catches a stale tree, because
# skills_freshness_test.dart is part of `dart test`.
skills:
	dart run bin/frx.dart update-skills --root ..

# The extension's generated constants — the `--kind` sets, the marker path and
# the doctor remedy ids, written from the CLI's own ArgParsers so the editor
# reads the contract instead of restating it. `make check` catches a stale copy,
# because contract_freshness_test.dart is part of `dart test`.
contract:
	dart run bin/gen_contract.dart

# The archive `frx create` unpacks — a derived artifact like docs/flows, and it
# goes stale the moment the product moves. `make check` catches that, because
# template_freshness_test.dart is part of `dart test`.
#
# None of the three flags is adjustable. `-f base64` keeps the payload a single
# string literal; `-f bytes` writes the same archive as a const list 4.7× the
# size. `-n frx` names the constant `create_command.dart` imports. The manifest
# is not passed because `pack` reads ../mold.yaml, beside the project it packs.
template:
	dart run mold:mold pack .. -f base64 -n frx -o lib/src/template/template.g.dart
	@echo "✓ $$(du -h lib/src/template/template.g.dart | cut -f1) embedded — run 'dart test test/template_freshness_test.dart' to confirm"

# --- teardown ----------------------------------------------------------------

uninstall:
	-$(CODE) $(PROFILE_ARG) --uninstall-extension pro100dev.frx
	-dart uninstall tools

clean:
	rm -rf $(EXT_DIR)/out $(EXT_DIR)/*.vsix
