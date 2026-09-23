#!/usr/bin/env bash
# Rebuild extractor_history.bundle + commit_hash_mapping.csv from the
# private macho_project monorepo's own git history. Run this again whenever
# apple_protobuf_extractor's real history changes (or to re-verify this
# checked-in copy against a fresh extraction) -- see reproducibility_archive/
# README.md's "Re-running the CFG-block tracer" section for the full
# rationale, recipe, and verification this was checked against when built
# (2026-09-15): an exact match against the real repository on all 22 CFG-
# tracked files, and every block count in a full build_cfg_report.py run.
#
# Requires:
#   - git >= 2.22 (macOS system /usr/local/bin/git may be older -- this repo
#     was built with /usr/bin/git 2.39.3; check `git --version` first)
#   - git-filter-repo (https://github.com/newren/git-filter-repo);
#     `pip3 install --user git-filter-repo` if missing
#
# Usage:
#   ./build_bundle.sh /path/to/macho_project [pin_commit_hash]
#
# pin_commit_hash defaults to dfff6a39cab5cba2f22862248ca616574f1de67f (this
# paper's population-pin commit, 2026-07-20 -- the same pin used everywhere
# else in the dataset/paper, since 2026-09-22; previously d767482, two days
# later, before the CFG-tracer's own pin was brought into line) and becomes
# the bundle's `paper-pin-dfff6a3` tag. Only meaningful if that commit is
# still real ancestry in the source repo.
#
# A later 2026-09-22 attempt to also exclude 15 sibling-subproject commits
# this bundle's own --path filter can't cleanly drop (so its population
# would exactly match data/dataset/output/commits/commits.json's 240,
# rather than being a superset) was reverted: even the smallest, most
# surgical version tried (excluding just 4 filenames unique to 3 of the 15)
# twice independently corrupted the pin commit itself via a git-filter-repo
# interaction not fully understood -- see conversation history 2026-09-22
# for the two independent failure modes hit. Left as a known, harmless
# population mismatch rather than risk a silent repeat: verified the 15
# is never a CFG block's traced origin, churn, or bridge commit, so it has
# zero effect on any published number -- see reproducibility_archive/
# README.md's Dataset section.
#
# 2026-09-23: the bundle used to also carry 21 commits after this pin (a
# side effect of bundling HEAD + the branch tip, not just the pin tag) --
# closed that gap since, unlike the 15 above, it needed no history rewrite
# at all: just bundling the pin tag alone, and filtering
# commit_hash_mapping.csv to ancestors of it. Population is now exactly
# 255 (240 + the 15 unavoidable sibling-subproject leaks).
#
# Writes extractor_history.bundle + commit_hash_mapping.csv into THIS
# directory (report_on_code_development/reproducibility_archive/
# extractor_git_history/), overwriting the checked-in copies.
#
# Safety: never runs git-filter-repo (a destructive, in-place history
# rewrite) against the real source repo -- always against a throwaway,
# fully-independent clone (--no-hardlinks --no-local, so no object storage
# is ever shared with the source) made in a scratch directory, deleted at
# the end. The source repo is only ever read from, via a plain `git clone`.
set -euo pipefail

SOURCE_REPO="${1:?Usage: $0 /path/to/macho_project [pin_commit_hash]}"
PIN_COMMIT="${2:-dfff6a39cab5cba2f22862248ca616574f1de67f}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

command -v git-filter-repo >/dev/null || {
    echo "git-filter-repo not found -- pip3 install --user git-filter-repo" >&2
    exit 1
}
git --version | awk '{print $3}' | { IFS=. read -r maj min _; [ "$maj" -gt 2 ] || { [ "$maj" -eq 2 ] && [ "$min" -ge 22 ]; }; } || {
    echo "git >= 2.22 required; found $(git --version). On macOS, try PATH=/usr/bin:\$PATH" >&2
    exit 1
}

echo "Cloning $SOURCE_REPO into isolated scratch clone (no shared object storage)..."
git clone --no-hardlinks --no-local "$SOURCE_REPO" "$SCRATCH/clone"
cd "$SCRATCH/clone"
git remote remove origin

echo "Filtering to apple_protobuf_extractor's full path history, plus its repo-root-level dependencies and adjacent tooling..."
# All four names apple_protobuf_extractor/ has carried: it started as this
# monorepo's own root commit (proto/, macho/ directly at top level, before
# any subprojects existed), moved into macho_extractor/ partway through,
# then renamed to apple_protobuf_extractor/ later still. Pure path
# filter, no renaming/content rewriting -- see README.md for why that
# matters (preserves git_tracer.py's own rename-bridging test cases).
#
# Widened 2026-09-22 beyond the original 4 paths: checked every commit
# hash referenced by the live 678-population evidence bundles (259
# distinct hashes) against this bundle and found only 73% covered -- the
# rest are real, in-window commits excluded purely because they touch
# files outside proto/macho/macho_extractor/apple_protobuf_extractor (repo
# root notes/tooling, or a mix of that plus extractor paths in one
# commit). Evidence-gathering also reruns historical commands via `git
# worktree add` (a full checkout), which additionally needs pytest.ini/
# requirements.txt/run_tests.py/tests/ at the repo root to actually run --
# a path filter can never guarantee every future rerun works, but this
# widened list covers everything the current 678-population evidence
# needs (259/259 hashes: 240 real commits now included, the other 19 are
# 2 false-positive hex-string matches + 2 non-existent + 15 commits that
# touch ONLY excluded paths, deliberately not pulled in -- see below).
#
# Deliberately still excluded (checked and confirmed each of the
# newly-covered commits doesn't need them): ios_decoder/, geo_traffic/
# and mitm_traffic_parser/ (the same subproject under its current and a
# prior name -- a separate research tool, not extractor development),
# tools/ and wt_oracle.py (created as part of that same geo_traffic work,
# despite the generic-sounding name), claude_prompts.txt and report/ +
# report_on_code_development/ (this paper's own materials, not the code
# under study), and every other top-level subproject in this monorepo
# (CS4404 2021-22/, CS7CS4_supplemental_2026/ -- teaching/grading
# material -- ogcio_wallet_investigation/, macho-disasm/, pixel8_*/,
# addon*/, report_on_apple_location_services/, report_on_test_quality/,
# eval/) -- none of which this archive should ever carry the git history
# of. A handful of missing commits are simply not recoverable this way:
# they touch only an excluded subproject's own files, which is correct.
git-filter-repo --force \
    --path proto --path macho --path macho_extractor --path apple_protobuf_extractor \
    --path .gitignore \
    --path CAUTIOUS_PORTABLE_TRANSPARENT_ANALYSIS.md \
    --path CODE_STRUCTURE_REVIEW.md \
    --path HEURISTIC_REGISTRY_RELABELS.md \
    --path LIMITATIONS.md \
    --path MACHO_EXTRACTOR_IMPORT_NOTICE.md \
    --path PROTO_DIFF_PLAN.md \
    --path PROTO_VALIDATION_NOTES.md \
    --path README.md \
    --path REPEATED_BYTES_NAME_RESOLUTION_FOLLOWUP.md \
    --path TODO.md \
    --path URL_REQUEST_PROTO_FINDER_PLAN.md \
    --path WRITETO_BUDGET_ANALYSIS.md \
    --path WRITETO_SWAP_PLAN.md \
    --path find_protobuf_for_url \
    --path heuristic_registry.py \
    --path iphone8_reference_protos \
    --path notes \
    --path proto_diff \
    --path proto_diff.py \
    --path proto_diff_llm_prototype.py \
    --path pytest.ini \
    --path requirements.txt \
    --path run_tests.py \
    --path tests \
    --path urlproto \
    --path validate_protos_candidates.py \
    --path validate_protos_classify.py \
    --path validate_protos_dump.py

echo "Verifying single-root, fully-linear ancestry (no subtree-merge surprises)..."
root_count="$(git log --max-parents=0 --oneline | wc -l | tr -d ' ')"
if [ "$root_count" != "1" ]; then
    echo "WARNING: expected exactly 1 root commit, found $root_count -- inspect before trusting this bundle" >&2
fi

echo "Tagging pin commit ($PIN_COMMIT)..."
new_pin="$(awk -v old="$PIN_COMMIT" '$1==old{print $2}' .git/filter-repo/commit-map)"
if [ -z "$new_pin" ]; then
    echo "ERROR: pin commit $PIN_COMMIT not found in filtered history (commit-map has no entry, or it maps to the null sha -- it may not touch any tracked path)" >&2
    exit 1
fi
git tag "paper-pin-${PIN_COMMIT:0:7}" "$new_pin"

echo "Building bundle (ref: paper-pin-${PIN_COMMIT:0:7} only -- just the pin's own"
echo "ancestry, not the branch tip, so no post-pin commits ride along)..."
git bundle create "$HERE/extractor_history.bundle" "paper-pin-${PIN_COMMIT:0:7}"
git bundle verify "$HERE/extractor_history.bundle"

echo "Writing commit_hash_mapping.csv (one row per ancestor-of-pin surviving commit)..."
python3 - "$HERE/commit_hash_mapping.csv" "$new_pin" <<'PYEOF'
import csv, subprocess, sys

out_path, new_pin = sys.argv[1], sys.argv[2]
with open(".git/filter-repo/commit-map") as f:
    pairs = [l.split() for l in f if l.strip() and not l.startswith("old")]

rows = []
for old, new in pairs:
    if new == "0" * 40:
        continue  # pruned -- didn't survive the path filter
    is_ancestor = subprocess.run(["git", "merge-base", "--is-ancestor", new, new_pin]).returncode == 0
    if not is_ancestor:
        continue  # not reachable from the bundled pin ref -- would be an orphan row
    subj = subprocess.run(["git", "log", "-1", "--format=%s", new],
                           capture_output=True, text=True, check=True).stdout.strip()
    rows.append((old, new, new[:7], subj))

with open(out_path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["original_commit_hash", "bundle_commit_hash", "short_hash", "commit_msg_subject"])
    w.writerows(rows)

print(f"{len(rows)} rows written to {out_path}")
PYEOF

echo "Done. Verify against the real repo before trusting a rebuild -- see"
echo "README.md's 'Re-running the CFG-block tracer' section for the exact"
echo "22-file-diff + full-corpus-block-count verification this was checked"
echo "against originally."
