#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp" 2>/dev/null || true; rm -rf "$tmp"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_exists() { [[ -d "$1" ]] || fail "expected $1 to exist"; }
assert_missing() { [[ ! -e "$1" ]] || fail "expected $1 to be removed"; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"; }
assert_no_branch() {
  git -C "$1" show-ref --verify --quiet "refs/heads/$2" && fail "expected branch $2 to be deleted" || true
}
assert_branch() {
  git -C "$1" show-ref --verify --quiet "refs/heads/$2" || fail "expected branch $2 to survive"
}

make_repo() {
  local repo="$1"
  git init -q -b main "$repo"
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.com
  touch "$repo/README"
  git -C "$repo" add README
  git -C "$repo" commit -qm initial
}

add_worktree() {
  local repo="$1" path="$2" branch="$3"
  git -C "$repo" worktree add -q -b "$branch" "$path"
}

add_locked_worktree() {
  add_worktree "$@"
  git -C "$1" worktree lock --reason test "$2"
}

run_tidy() {
  local repo="$1"
  (cd "$repo" && GH_TIDY_DEV_MODE=true "$script_dir/gh-tidy" \
    --auto-delete-merged --skip-gc --skip-prune --skip-update-check --trunk main) 2>&1
}

repo="$tmp/clean"
worktree="$tmp/clean-landed"
make_repo "$repo"
add_locked_worktree "$repo" "$worktree" topic
output=$(run_tidy "$repo")
assert_missing "$worktree"

# An unlocked worktree is swept on the same terms as a locked one - it holds its
# branch hostage just as effectively.  The main worktree must survive regardless.
repo="$tmp/unlocked"
worktree="$tmp/unlocked-landed"
make_repo "$repo"
add_worktree "$repo" "$worktree" topic
output=$(run_tidy "$repo")
assert_missing "$worktree"
assert_exists "$repo"
assert_no_branch "$repo" topic
assert_branch "$repo" main

# A landed worktree with uncommitted changes goes too, once they are saved - on a ref
# of their own, so the user's stash is left exactly as it was.
repo="$tmp/unlocked-dirty"
worktree="$tmp/unlocked-dirty-worktree"
make_repo "$repo"
add_worktree "$repo" "$worktree" topic
echo scratch > "$worktree/untracked"
echo edit >> "$worktree/README"
echo mine >> "$repo/README"
git -C "$repo" stash push -q -m mine
output=$(run_tidy "$repo")
assert_missing "$worktree"
assert_no_branch "$repo" topic
[[ "$(git -C "$repo" stash list)" == "stash@{0}: On main: mine" ]] || fail "expected the user's stash untouched"
saved=$(git -C "$repo" for-each-ref --format='%(refname)' refs/gh-tidy/leftovers/topic)
[[ -n "$saved" ]] || fail "expected the changes saved under refs/gh-tidy/leftovers/topic"
assert_contains "$output" "git stash apply $saved"
# The restore command the output gives must bring back both kinds of change.
git -C "$repo" worktree add -q --detach "$tmp/restored" "$saved^1"
git -C "$tmp/restored" stash apply -q "$saved"
assert_contains "$(cat "$tmp/restored/untracked")" scratch
assert_contains "$(cat "$tmp/restored/README")" edit

# Locked, a slash in the branch name, and a space in the path.
repo="$tmp/dirty"
worktree="$tmp/dirty landed"
make_repo "$repo"
add_locked_worktree "$repo" "$worktree" feat/dirty
touch "$worktree/dirty"
output=$(run_tidy "$repo")
assert_missing "$worktree"
assert_no_branch "$repo" feat/dirty
assert_contains "$output" "?? dirty"
[[ -n "$(git -C "$repo" for-each-ref refs/gh-tidy/leftovers/feat/dirty)" ]] || fail "expected the changes saved"

# Without --auto-delete-merged and no terminal to ask on, nothing is saved or removed.
repo="$tmp/not-interactive"
worktree="$tmp/not-interactive-worktree"
make_repo "$repo"
add_worktree "$repo" "$worktree" topic
touch "$worktree/scratch"
output=$(cd "$repo" && GH_TIDY_DEV_MODE=true GH_TIDY_AUTO_DELETE_MERGED=false "$script_dir/gh-tidy" \
  --skip-gc --skip-prune --skip-update-check --trunk main </dev/null 2>&1)
assert_contains "$output" "Not interactive, skipping"
[[ -e "$worktree/scratch" ]] || fail "expected the worktree and its untracked file to survive"
assert_branch "$repo" topic
[[ -z "$(git -C "$repo" for-each-ref refs/gh-tidy)" ]] || fail "expected nothing saved without consent"

repo="$tmp/unlanded"
worktree="$tmp/unlanded-worktree"
make_repo "$repo"
add_locked_worktree "$repo" "$worktree" topic
touch "$worktree/unlanded"
git -C "$worktree" add unlanded
git -C "$worktree" commit -qm unlanded
touch "$worktree/scratch"
gh() { return 0; }
export -f gh
output=$(run_tidy "$repo")
unset -f gh
assert_exists "$worktree"
assert_contains "$output" "not landed"
# Unlanded: neither the worktree, its uncommitted changes, nor its branch may be touched.
[[ -e "$worktree/scratch" ]] || fail "expected the unlanded worktree's untracked file to survive"
assert_branch "$repo" topic

repo="$tmp/lookup-failure"
worktree="$tmp/lookup-failure-worktree"
make_repo "$repo"
add_locked_worktree "$repo" "$worktree" topic
touch "$worktree/unlanded"
git -C "$worktree" add unlanded
git -C "$worktree" commit -qm unlanded
gh() { return 1; }
export -f gh
output=$(run_tidy "$repo")
unset -f gh
assert_exists "$worktree"
assert_contains "$output" "lookup failed"

repo="$tmp/older-pr"
worktree="$tmp/older-pr-worktree"
make_repo "$repo"
add_locked_worktree "$repo" "$worktree" review/pr-73
touch "$worktree/older-pr"
git -C "$worktree" add older-pr
git -C "$worktree" commit -qm older-pr
GH_TIDY_TEST_MATCH_HEAD=$(git -C "$worktree" rev-parse HEAD)
gh() {
  if [[ "$1" == api && "$3" == "repos/{owner}/{repo}/commits/$GH_TIDY_TEST_MATCH_HEAD/pulls" ]]; then
    echo 0000000000000000000000000000000000000000
    echo "$GH_TIDY_TEST_MATCH_HEAD"
  fi
  return 0
}
export GH_TIDY_TEST_MATCH_HEAD
export -f gh
output=$(run_tidy "$repo")
unset -f gh
assert_missing "$worktree"
# The worktree pass proved this head landed - the branch must go with it, since it
# is squash-merged (not an ancestor of main) and so invisible to 'git branch --merged'.
assert_no_branch "$repo" review/pr-73

# A squash-merged branch with no worktree at all: only the head-commit lookup finds
# it.  Nothing here is an ancestor of main, and the branch is not authored by @me.
repo="$tmp/squashed-no-worktree"
make_repo "$repo"
git -C "$repo" branch review/pr-80
git -C "$repo" branch keep/unlanded
for b in review/pr-80 keep/unlanded; do
  git -C "$repo" checkout -q "$b"
  touch "$repo/${b//\//-}-file"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "$b"
done
git -C "$repo" checkout -q main
GH_TIDY_TEST_MATCH_HEAD=$(git -C "$repo" rev-parse review/pr-80)
gh() {
  if [[ "$1 $2" == "repo view" ]]; then
    echo github.example.com
  elif [[ "$1" == api && "$2" == --hostname && "$3" == github.example.com \
    && "$5" == "repos/{owner}/{repo}/commits/$GH_TIDY_TEST_MATCH_HEAD/pulls" ]]; then
    echo "$GH_TIDY_TEST_MATCH_HEAD"
  fi
  return 0
}
export GH_TIDY_TEST_MATCH_HEAD
export -f gh
output=$(run_tidy "$repo")
unset -f gh
assert_no_branch "$repo" review/pr-80
assert_branch "$repo" keep/unlanded
assert_branch "$repo" main

repo="$tmp/missing"
worktree="$tmp/missing-worktree"
make_repo "$repo"
add_locked_worktree "$repo" "$worktree" topic
rm -rf "$worktree"
output=$(run_tidy "$repo")
assert_contains "$(git -C "$repo" worktree list --porcelain)" "locked test"
assert_contains "$output" "directory is gone"

# Unlocked and its directory is gone: 'git worktree prune' reaps it outright, so it
# never reaches the loop and the user is never asked about it.
repo="$tmp/missing-unlocked"
worktree="$tmp/missing-unlocked-worktree"
make_repo "$repo"
add_worktree "$repo" "$worktree" topic
rm -rf "$worktree"
output=$(run_tidy "$repo")
[[ "$(git -C "$repo" worktree list --porcelain)" != *"missing-unlocked-worktree"* ]] \
  || fail "expected pruning to drop the stale worktree record"
[[ "$output" != *"directory is gone"* ]] || fail "should not have prompted about a prunable worktree"

repo="$tmp/remove-failure"
worktree="$tmp/remove-failure-worktree"
submodule="$tmp/submodule"
git init -q -b main "$submodule"
git -C "$submodule" config user.name test
git -C "$submodule" config user.email test@example.com
touch "$submodule/README"
git -C "$submodule" add README
git -C "$submodule" commit -qm initial
make_repo "$repo"
git -C "$repo" -c protocol.file.allow=always submodule add -q "$submodule" vendor/submodule
git -C "$repo" commit -qm 'add submodule'
add_locked_worktree "$repo" "$worktree" topic
git -C "$worktree" -c protocol.file.allow=always submodule update --init -q
echo keep > "$worktree/scratch"
git -C "$worktree" add scratch
output=$(run_tidy "$repo" || true)
assert_contains "$(git -C "$repo" worktree list --porcelain)" "locked"
assert_contains "$output" "Unable to remove worktree"
# The removal failed, so the changes saved for it must be back where they were, staged
# ones included.
assert_contains "$(cat "$worktree/scratch")" keep
assert_contains "$(git -C "$worktree" diff --cached --name-only)" scratch
[[ -z "$(git -C "$repo" for-each-ref refs/gh-tidy)" ]] || fail "expected no leftovers ref after restoring"

# Only a submodule is dirty: 'stash push' saves nothing yet still exits 0.  The worktree
# must be kept, and the user's own stash must not be mistaken for the save.
repo="$tmp/dirty-submodule"
worktree="$tmp/dirty-submodule-worktree"
make_repo "$repo"
git -C "$repo" -c protocol.file.allow=always submodule add -q "$submodule" vendor/submodule
git -C "$repo" commit -qm 'add submodule'
add_worktree "$repo" "$worktree" topic
git -C "$worktree" -c protocol.file.allow=always submodule update --init -q
echo dirty >> "$worktree/vendor/submodule/README"
echo mine >> "$repo/README"
git -C "$repo" stash push -q -m mine
output=$(run_tidy "$repo")
assert_contains "$output" "Unable to save"
assert_contains "$(cat "$worktree/vendor/submodule/README")" dirty
[[ "$(git -C "$repo" stash list)" == "stash@{0}: On main: mine" ]] || fail "expected the user's stash untouched"

echo "PASS: locked worktree cleanup"
