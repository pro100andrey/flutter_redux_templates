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
.PHONY: help install cli ext package ext-install profiles dist version check test docs skills contract template uninstall clean

help:
	@echo "frx — CLI $(shell sed -n 's/^version: //p' pubspec.yaml | head -1) · extension $(EXT_VERSION)"
	@echo
	@echo "  make install [PROFILE=<name>]   CLI + extension (the everyday one)"
	@echo "  make cli                        dart install the frx binary onto PATH"
	@echo "  make ext     [PROFILE=<name>]   compile, package and install the extension"
	@echo "  make package                    build the VSIX only"
	@echo "  make profiles                   list VSCode profiles + the frx build in each"
	@echo
	@echo "  make dist                       compile a native frx binary into dist/"
	@echo "  make version V=<x.y.z>          bump the three version declarations at once"
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

# --- release -----------------------------------------------------------------

# The same binary the release workflow attaches, for this machine only —
# `dart compile exe` builds for the host and does not cross-compile. Worth having
# locally to check what an install actually gets: `dart install` and `dart run`
# both take different paths through the SDK than an AOT snapshot does.
dist:
	dart pub get
	@mkdir -p dist
	dart compile exe bin/frx.dart -o dist/frx
	@./dist/frx --version && du -h dist/frx | cut -f1

# One version, declared in three files, and the release refuses a tag they
# disagree with — so bumping them by hand is three chances to publish a binary
# that reports a version it is not. `version_test.dart` is what catches that;
# this is what avoids it.
version:
	@test -n "$(V)" || { echo "usage: make version V=0.3.0"; exit 1; }
	@echo "$(V)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+([-+].+)?$$' || { echo "\"$(V)\" is not a semantic version"; exit 1; }
	@# perl, not sed: in-place editing is `-i ''` on BSD and `-i` on GNU, and a
	@# Makefile that works on the author's machine only is how this goes wrong.
	@perl -pi -e "s/^version: .*/version: $(V)/" pubspec.yaml
	@perl -pi -e "s/frxVersion = '[^']*'/frxVersion = '$(V)'/" lib/src/version.dart
	@cd $(EXT_DIR) && npm version "$(V)" --no-git-tag-version --allow-same-version >/dev/null
	@dart test test/version_test.dart >/dev/null && echo "✓ pubspec, version.dart and package.json all say $(V)"
	@echo
	@echo "  git commit -am 'v$(V)' && git tag v$(V) && git push origin main v$(V)"

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
	rm -rf $(EXT_DIR)/out $(EXT_DIR)/*.vsix dist
