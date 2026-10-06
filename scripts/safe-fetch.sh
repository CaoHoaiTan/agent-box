#!/usr/bin/env bash
set -euo pipefail

die() { echo "safe-fetch: $*" >&2; exit 1; }
if [[ $# == 1 && ( "$1" == --help || "$1" == -h ) ]]; then
  echo 'Usage: safe-fetch.sh <workspace-repo-path> <branch> <clean-clone-path>'
  exit 0
fi
[[ $# == 3 ]] || die 'expected workspace repo, branch and clean clone; use --help.'
command -v realpath >/dev/null 2>&1 || die 'realpath is required.'
[[ -d "$1" && -d "$3" ]] || die 'both repository directories must exist.'
source_repo="$(realpath "$1")"
branch="$2"
clean_clone="$(realpath "$3")"
[[ "$source_repo" != "$clean_clone" ]] || die 'source and clean clone must differ.'
case "$clean_clone/" in "$source_repo/"*) die 'clean clone is inside the source repo.' ;; esac
case "$source_repo/" in "$clean_clone/"*) die 'source repo is inside the clean clone.' ;; esac

# Inspect structure only: invoking Git on the agent's worktree can run its config.
# Linked worktrees are deliberately refused; their .git file may point elsewhere.
if [[ -d "$source_repo/.git" && ! -L "$source_repo/.git" ]]; then
  source_git="$source_repo/.git"
elif [[ -f "$source_repo/HEAD" && -d "$source_repo/objects" ]]; then
  source_git="$source_repo"
else
  die 'source must be a normal Git repository or a bare repository (no linked worktrees).'
fi
[[ -f "$source_git/HEAD" && -d "$source_git/objects" ]] || die 'source Git structure is incomplete.'
[[ -d "$clean_clone/.git" && ! -L "$clean_clone/.git" ]] || die 'clean clone must be an independent, normal Git clone.'

# Keep inherited worktree overrides from redirecting our clean-clone commands.
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
export GIT_TERMINAL_PROMPT=0
clean_git() {
  git --no-pager -C "$clean_clone" -c core.hooksPath=/dev/null \
    -c core.fsmonitor=false -c color.ui=false -c protocol.ext.allow=never \
    -c protocol.file.allow=always -c safe.directory="$source_repo" "$@"
}
clean_git rev-parse --is-inside-work-tree >/dev/null
clean_git check-ref-format "refs/heads/$branch" || die 'invalid branch name.'
clean_git check-ref-format --branch "$branch" >/dev/null || die 'invalid branch name.'
[[ "$branch" != main ]] || die 'refusing to overwrite the review baseline main.'
branch_ref="refs/heads/$branch"
review_range="refs/heads/main...$branch_ref"
clean_git show-ref --verify --quiet refs/heads/main || die 'clean clone needs a local main branch.'

# An absolute path, full refs and no submodules prevent remote helper
# or submodule URLs in the untrusted source from requesting host credentials.
clean_git -c fetch.fsckObjects=true fetch --no-recurse-submodules --no-tags \
  -- "$source_repo" "$branch_ref:$branch_ref"
clean_git merge-base refs/heads/main "$branch_ref" >/dev/null || die 'fetched branch has no common ancestor with main; review refused.'
changed_files="$(mktemp "${TMPDIR:-/tmp}/agentbox-fetch.XXXXXX")"
trap 'rm -f -- "$changed_files"' EXIT
# Check diff's status directly; process substitution would hide a failed diff.
clean_git diff --no-ext-diff --no-textconv --name-only -z "$review_range" -- > "$changed_files"

echo 'Commits (main..branch):'
clean_git log --oneline "refs/heads/main..$branch_ref" --
echo 'Changed files (main...branch):'
while IFS= read -r -d '' path; do
  printf '  %q\n' "$path"
done < "$changed_files"
echo 'Review these executable/configuration changes carefully:'
warned=0
while IFS= read -r -d '' path; do
  case "$path" in
    package.json|*/package.json|*lock*|*.sh|Makefile|*/Makefile|Dockerfile|*/Dockerfile|.github/*|.husky/*|.vscode/*|.claude/*|.codex/*)
      printf '  WARNING: %q\n' "$path"
      warned=1
      ;;
  esac
done < "$changed_files"
[[ "$warned" == 1 ]] || echo '  None of the listed risky paths changed; review the full diff anyway.'

echo 'Nothing was pushed. Review from the clean clone; these diff options disable external diff/textconv programs:'
printf '  git -C %q -c core.hooksPath=/dev/null -c core.fsmonitor=false diff --no-ext-diff --no-textconv %q --\n' "$clean_clone" "$review_range"
printf '  git -C %q -c core.hooksPath=/dev/null -c core.fsmonitor=false switch --no-guess -- %q\n' "$clean_clone" "$branch"
echo 'After reviewing code and executable configuration, push manually:'
printf '  git -C %q -c core.hooksPath=/dev/null -c core.fsmonitor=false push origin %q\n' "$clean_clone" "$branch_ref:$branch_ref"
echo 'Fetched commits retain their original signatures. To sign with your own key, review then cherry-pick -S into a new host branch before pushing.'
