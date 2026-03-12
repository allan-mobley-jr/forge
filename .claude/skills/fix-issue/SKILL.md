---
name: fix-issue
description: >
  Work through a GitHub issue end-to-end: branch, plan, implement,
  self-review, PR, and wait for merge. Use this skill whenever the user
  wants to fix a bug, implement a feature, or tackle any issue from the
  backlog — even if they don't say "/fix-issue" explicitly. Trigger when
  the user mentions working on an issue (by number or description), asks
  to pick up the next issue, or requests the full branch-to-PR workflow.
  Invoke with /fix-issue <number> or /fix-issue for the next open issue.
  One issue at a time — finish before starting the next.
allowed-tools: Bash(gh *), Bash(git *), Read, Write, Edit, MultiEdit, Glob, Grep, WebSearch, WebFetch
---

# /fix-issue — Issue-to-PR Workflow

Work through one GitHub issue from start to finish. One issue at a time, sequential and thorough.

## Usage

```
/fix-issue <issue-number>
/fix-issue           # picks the lowest open issue
```

## Process

### Step 1: Pick the issue

If no issue number is given, find the lowest-numbered open issue:

```bash
gh issue list --state open --limit 100 --json number,title,body --jq 'sort_by(.number) | .[0]'
```

Read the issue thoroughly. Understand what needs to change and why.

### Step 2: Create a branch

Branch name format: `fix/<issue-number>-<short-slug>` for bugs, `feat/<number>-<slug>` for features.

```bash
git checkout main && git pull
git checkout -b fix/<number>-<slug>   # or feat/<number>-<slug>
```

The slug should be 2-4 words from the issue title, kebab-case. Example: `fix/94-doctor-skills-outdated`

### Step 3: Research

Before discussing or planning, gather the information you need:

**Codebase:**
1. Search for files, functions, and patterns related to the issue.
2. Read every file that may need to change.
3. Trace the relevant code paths — understand how the pieces connect.
4. Note any constraints, edge cases, or dependencies you discover.

**Validate the premise:**
5. Verify the issue's assumptions against the **current** code. Issues may have been filed against an older version of the codebase — other PRs may have changed the relevant code paths since then.
6. Confirm the problem actually exists. Trace the exact scenario described in the issue and check whether the current code already handles it.

**Web (when needed):**
If the issue involves unfamiliar APIs, libraries, protocols, or domain concepts, search the web to fill knowledge gaps. Don't guess — look it up.

This step is about gathering facts, not forming opinions yet.

### Step 4: Discuss the issue

Before planning or writing any code, present your understanding to the user and get alignment:

1. **Challenge the premise first.** Does the problem described in the issue still exist? If the codebase has changed since filing, say so. Don't propose a fix for a problem that isn't there.
2. Summarize what the issue is asking for in your own words.
3. Identify the relevant files and areas of the codebase.
4. Call out any ambiguity, open questions, or trade-offs you see.
5. Ask the user if your understanding is correct and whether they have preferences on approach.

**Do not proceed until the user confirms.** This is a checkpoint — the user may have context that changes the approach entirely.

### Step 5: Plan the fix

Before writing any code:

1. Identify the root cause (not just the symptom).
2. Consider side effects — will this fix break something else?
3. State the plan in 1-3 sentences. If you can't, the issue is too big — split it.

### Step 6: Implement the fix

- Make the smallest change that fully addresses the issue.
- Follow the conventions in CLAUDE.md — atomic commits, one concern per commit.
- Don't refactor surrounding code, add comments to unchanged code, or "improve" things that aren't broken.

### Step 7: Self-review

Before pushing, review your own work:

1. `git diff` — read every line. Does each change serve the fix?
2. Does the fix actually address the root cause from the issue?
3. Are there any unintended side effects?
4. Would you approve this PR if someone else wrote it?

If anything is off, fix it before proceeding.

### Step 8: Commit, push, and create PR

Commit with a message that references the issue:

```bash
git add <specific-files>
git commit -m "fix: <what changed>

Closes #<number>"
```

Push and create the PR:

```bash
git push -u origin fix/<number>-<slug>
gh pr create --title "<short title>" --body "$(cat <<'EOF'
## Summary
<1-3 bullets explaining what changed and why>

Closes #<number>

## Test plan
<how to verify the fix>
EOF
)"
```

### Step 9: Wait for PR review

After creating the PR, stop and tell the user:

```
PR created: <url>
Waiting for review. Run /resolve-pr-comments when review feedback comes in.
After the PR merges, run /fix-issue to pick up the next issue.
```

Do NOT start the next issue automatically. Wait for the current PR to merge first.

## Rules

- **One issue at a time.** Don't batch. Don't parallelize. Finish one before starting the next.
- **Always start from main.** Pull latest before branching.
- **Branch naming is mandatory.** `fix/<number>-<slug>` for bugs, `feat/<number>-<slug>` for features.
- **Read before you write.** Never modify a file you haven't read in this session.
- **Smallest fix wins.** If you're touching more than 3 files, reconsider whether the issue scope is right.
- **After a PR merges**, clean up: `git checkout main && git pull && git branch -d <branch> && git remote prune origin`
