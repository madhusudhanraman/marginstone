#!/bin/bash
# All untrusted values are positional arguments. Never evaluate capture text as shell code.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND='ssh -o BatchMode=yes -o ConnectTimeout=15'
command_name="${1:?}"; shift
fail() { echo "$*" >&2; exit 1; }
valid_path() { [[ "$1" == _posts/*.md && "${1#_posts/}" != */* && "${1#_posts/}" != .* && "$1" != *$'\n'* && "$1" != *'\'* ]]; }
commit_file() {
  local tree="$1" path="$2" message="$3" name email
  name="$(git -C "$tree" config user.name || true)"; email="$(git -C "$tree" config user.email || true)"
  git -C "$tree" -c user.name="${name:-Nautilus}" -c user.email="${email:-nautilus@localhost}" commit --only -m "$message" -- "$path"
}
case "$command_name" in
remote) git -C "${1:?}" remote get-url origin ;;
configure-keychain)
  git -C "${1:?}" config --local credential.https://github.com.useHttpPath true
  git -C "$1" config --local --replace-all credential.https://github.com.helper ''
  git -C "$1" config --local --add credential.https://github.com.helper osxkeychain
  ;;
check-upload)
  git -C "${1:?}" push --dry-run origin "HEAD:refs/heads/${2:?}"
  ;;

setup)
  repo="${1:?}"; tree="${2:?}"
  root="$(git -C "$repo" rev-parse --show-toplevel)" || fail 'This is not a Git checkout. Choose the local clone used by GitHub Desktop, rather than a downloaded ZIP folder.'
  [[ "$root" == "$repo" && -d "$repo/_posts" ]] || fail 'Choose the root of your Field Notes Git checkout (the folder containing _posts).'
  branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD)" || fail 'Your website checkout needs a named branch.'
  [[ "$branch" != nautilus/* ]] || fail 'Choose your normal website checkout, not the app’s drafts checkout.'
  if [[ -e "$tree" ]]; then
    [[ "$(git -C "$tree" rev-parse --path-format=absolute --git-common-dir)" == "$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)" ]] || fail 'Draft folder belongs to another repository.'
    [[ "$(git -C "$tree" symbolic-ref --short HEAD)" == nautilus/drafts ]] || fail 'Draft folder is on an unexpected branch.'
  elif git -C "$repo" show-ref --verify --quiet refs/heads/nautilus/drafts; then
    git -C "$repo" worktree add "$tree" nautilus/drafts
  else
    git -C "$repo" worktree add -b nautilus/drafts "$tree" "$branch"
  fi
  echo "NAUTILUS_BRANCH=$branch"
  ;;
commit)
  tree="${1:?}"; path="${2:?}"; valid_path "$path" || fail 'Invalid post path.'
  [[ "$(git -C "$tree" symbolic-ref --short HEAD)" == nautilus/drafts ]] || fail 'Draft branch changed; capture remains saved locally.'
  if [[ -n "$(git -C "$tree" status --porcelain -- "$path")" ]]; then
    git -C "$tree" add -- "$path"
    commit_file "$tree" "$path" 'Save passage with Marginstone'
  fi
  ;;
push-drafts)
  git -C "${1:?}" push origin refs/heads/nautilus/drafts:refs/heads/nautilus/drafts
  ;;
check-publish)
  repo="${1:?}"; branch="${2:?}"; path="${3:?}"; valid_path "$path" || fail 'Invalid post path.'
  [[ "$(git -C "$repo" symbolic-ref --short HEAD)" == "$branch" ]] || fail 'Switch the website checkout back to its configured publication branch before publishing.'
  [[ -z "$(git -C "$repo" status --porcelain -- "$path")" ]] || fail 'This post has local edits. Commit or move those edits before publishing it through the app.'
  for state in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [[ ! -e "$(git -C "$repo" rev-parse --git-path "$state")" ]] || fail 'Finish the Git merge or rebase before publishing.'
  done
  git -C "$repo" fetch origin "$branch"
  [[ "$(git -C "$repo" rev-parse HEAD)" == "$(git -C "$repo" rev-parse FETCH_HEAD)" ]] || fail 'Your website checkout and GitHub differ. Pull or push your existing changes, then try Publish again.'
  ;;
publish)
  repo="${1:?}"; branch="${2:?}"; path="${3:?}"; expected="${4:?}"; valid_path "$path" || fail 'Invalid post path.'
  [[ "$(git -C "$repo" symbolic-ref --short HEAD)" == "$branch" && "$(git -C "$repo" rev-parse HEAD)" == "$expected" ]] || fail 'The website branch changed during publication. The generated post remains in your checkout for review.'
  if [[ -n "$(git -C "$repo" status --porcelain -- "$path")" ]]; then
    git -C "$repo" add -- "$path"
    commit_file "$repo" "$path" 'Publish reading excerpts from Marginstone'
  fi
  git -C "$repo" push origin "HEAD:refs/heads/$branch"
  ;;
head) git -C "${1:?}" rev-parse HEAD ;;
*) fail 'Unknown repository operation.' ;;
esac
