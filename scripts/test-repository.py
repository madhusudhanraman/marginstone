#!/usr/bin/env python3
"""Integration tests for the exact repository helper shipped inside the app."""
import os
import subprocess
import tempfile
from pathlib import Path

HELPER = Path(__file__).resolve().parents[1] / 'Sources/Marginstone/Resources/repository.sh'

def git(folder, *args, ok=True):
    p = subprocess.run(['git', '-C', str(folder), *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if ok and p.returncode: raise AssertionError(p.stdout)
    return p

def helper(*args, ok=True):
    p = subprocess.run(['bash', str(HELPER), *map(str,args)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if ok and p.returncode: raise AssertionError(p.stdout)
    return p

with tempfile.TemporaryDirectory(prefix='marginstone-git-') as temp:
    root = Path(temp).resolve(); remote = root/'remote.git'; repo = root/'website with spaces'; tree = root/'Marginstone drafts'
    subprocess.run(['git','init','--bare',str(remote)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    git(root,'clone',str(remote),str(repo)); git(repo,'config','user.name','Test Reader'); git(repo,'config','user.email','reader@example.test')
    git(repo,'checkout','-b','master'); (repo/'_posts').mkdir()
    post='_posts/2026-10-16-bellow-herzog.md'
    (repo/post).write_text('---\ntitle: Herzog (1964)\nauthor: Saul Bellow\ncategories:\n  - Books\n---\nOriginal review.\n')
    (repo/'unrelated.txt').write_text('original\n'); git(repo,'add','.'); git(repo,'commit','-m','Initial'); git(repo,'push','-u','origin','master')
    git(remote,'symbolic-ref','HEAD','refs/heads/master')
    initial=git(repo,'rev-parse','HEAD').stdout.strip()
    remote_before=git(remote,'rev-parse','master').stdout.strip()
    helper('check-upload',repo,'master')
    assert git(remote,'rev-parse','master').stdout.strip()==remote_before, 'connection test uploaded changes'
    assert 'MARGINSTONE_BRANCH=master' in helper('setup',repo,tree).stdout
    assert git(repo,'symbolic-ref','--short','HEAD').stdout.strip()=='master'
    assert git(tree,'symbolic-ref','--short','HEAD').stdout.strip()=='nautilus/drafts'
    with (tree/post).open('a') as f: f.write('\n## Excerpts\n\n> Quote with $HOME and `literal backticks`.\n')
    helper('commit',tree,post); draft_head=git(tree,'rev-parse','HEAD').stdout.strip()
    helper('commit',tree,post); assert git(tree,'rev-parse','HEAD').stdout.strip()==draft_head, 'retry must be idempotent'
    helper('push-drafts',tree)
    assert git(repo,'rev-parse','HEAD').stdout.strip()==initial, 'capture changed website branch'
    assert 'Quote' not in (repo/post).read_text()
    assert git(remote,'show','refs/heads/nautilus/drafts:'+post).returncode==0
    helper('setup',repo,tree) # reconnect reuses the existing worktree
    assert helper('commit',tree,'_posts/../../escape.md',ok=False).returncode!=0
    assert helper('commit',tree,'_posts/.hidden.md',ok=False).returncode!=0
    (repo/post).write_text('Manual edit\n')
    assert helper('check-publish',repo,'master',post,ok=False).returncode!=0, 'must refuse an edited post'
    git(repo,'restore','--',post)
    (repo/'unrelated.txt').write_text('staged personal edit\n'); git(repo,'add','unrelated.txt')
    helper('check-publish',repo,'master',post)
    head=helper('head',repo).stdout.strip()
    with (repo/post).open('a') as f: f.write('\n## Excerpts\n\n> Quote.\n')
    helper('publish',repo,'master',post,head)
    assert git(repo,'diff','--cached','--name-only').stdout.strip()=='unrelated.txt', 'publish stole unrelated staged edits'
    assert git(repo,'show','HEAD:unrelated.txt').stdout=='original\n'
    assert '> Quote.' in git(remote,'show','refs/heads/master:'+post).stdout
    assert helper('check-publish',repo,'other-branch',post,ok=False).returncode!=0
    # A remote advance must never be overwritten by Publish.
    other=root/'other'; git(root,'clone',str(remote),str(other));git(other,'config','user.name','Other');git(other,'config','user.email','other@example.test')
    (other/'remote.txt').write_text('new change');git(other,'add','.');git(other,'commit','-m','Remote advance');git(other,'push','origin','master')
    assert helper('check-publish',repo,'master',post,ok=False).returncode!=0
    # Failure to sync must leave committed captures recoverable locally.
    git(tree,'remote','set-url','origin',str(root/'does-not-exist'))
    assert helper('push-drafts',tree,ok=False).returncode!=0
    assert git(tree,'rev-parse','HEAD').stdout.strip()==draft_head
    print('PASS: draft isolation, real commits/pushes, reconnect, retry idempotency, unsafe paths, dirty-post refusal, explicit publication, preservation of staged edits, wrong-branch refusal, remote divergence, offline recovery.')
