---
name: fix-issue
description: Work through a GitHub issue end-to-end — branch, plan, implement, review, PR, wait for merge. Use when tackling issues from the backlog one at a time.
allowed-tools: Bash(gh *), Bash(git *), Read, Glob, Grep, Edit, Write, Agent
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
gh issue list --state open --limit 1 --json number,title,body --jq '.[0]'
```

Read the issue thoroughly. Understand what needs to change and why.

### Step 2: Create a branch

Branch name format: `fix/<issue-number>-<short-slug>`

```bash
git checkout main && git pull
git checkout -b fix/<number>-<slug>
```

The slug should be 2-4 words from the issue title, kebab-case. Example: `fix/94-doctor-skills-outdated`

### Step 3: Plan the fix

Before writing any code:

1. Read every file that will be touched.
2. Identify the root cause (not just the symptom).
3. Consider side effects — will this fix break something else?
4. State the plan in 1-3 sentences. If you can't, the issue is too big — split it.

### Step 4: Implement the fix

- Make the smallest change that fully addresses the issue.
- Follow the conventions in CLAUDE.md — atomic commits, one concern per commit.
- Don't refactor surrounding code, add comments to unchanged code, or "improve" things that aren't broken.

### Step 5: Self-review

Before pushing, review your own work:

1. `git diff` — read every line. Does each change serve the fix?
2. Does the fix actually address the root cause from the issue?
3. Are there any unintended side effects?
4. Would you approve this PR if someone else wrote it?

If anything is off, fix it before proceeding.

### Step 6: Commit, push, and create PR

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

### Step 7: Wait for PR review

After creating the PR, stop and tell the user:

```
PR created: <url>
Waiting for review. Run /fix-issue to pick up the next issue, or /resolve-pr-comments if review feedback comes in.
```

Do NOT start the next issue automatically. Wait for the user to direct you.

## Rules

- **One issue at a time.** Don't batch. Don't parallelize. Finish one before starting the next.
- **Always start from main.** Pull latest before branching.
- **Branch naming is mandatory.** `fix/<number>-<slug>` for bugs, `feat/<number>-<slug>` for features.
- **Read before you write.** Never modify a file you haven't read in this session.
- **Smallest fix wins.** If you're touching more than 3 files, reconsider whether the issue scope is right.
- **After a PR merges**, clean up: `git checkout main && git pull && git branch -d <branch> && git remote prune origin`
