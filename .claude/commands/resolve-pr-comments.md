---
name: resolve-pr-comments
description: Use when a PR has review comments that need to be addressed, challenged, and resolved — especially from automated reviewers like GitHub Copilot
allowed-tools: Bash(gh *), Bash(git *), Read, Glob, Grep, Edit, Write
---

# /resolve-pr-comments — Review Comment Handler

Address PR review comments with skepticism. Take nothing at face value. Challenge everything. Respond and resolve.

## Process

### Step 1: Fetch the review comments

Identify the open PR for the current branch:

```bash
gh pr view --json number,url,reviews,reviewRequests --jq '{number, url}'
```

Then fetch all review comments:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments --jq '.[] | {id, path, line, body, user: .user.login, in_reply_to_id}'
```

Group comments by thread (use `in_reply_to_id` to identify replies vs top-level comments). Focus on unresolved threads only.

### Step 2: Evaluate each comment

For every review comment, before implementing anything:

1. **Read the suggestion carefully.** Understand what is being asked.
2. **Check the codebase.** Is the reviewer correct about how the code works? Do they have full context?
3. **Challenge the premise.** Is the suggestion actually an improvement, or is it based on a misunderstanding?
4. **Assess impact.** Would this change break something else? Is it solving a real problem or a hypothetical one?

Ask yourself:
- Is this technically correct for THIS codebase?
- Does the reviewer understand the full context?
- Would this break existing functionality?
- Is this a real issue or a style preference?
- Does this violate YAGNI?

### Step 3: Respond

For each comment thread, take one of two actions:

**If the suggestion is correct:** Fix it. Reply with what you changed and where. No flattery — just state the fix.

**If the suggestion is wrong or unnecessary:** Push back with technical reasoning. Reference the code, explain why the current approach is intentional, or ask a clarifying question.

Reply in the comment thread, not as a top-level PR comment:

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments/{comment_id}/replies -f body="Your response"
```

### Step 4: Commit fixes

If any changes were made, commit them as a single atomic commit (or split by concern if changes are independent). Push to the PR branch.

### Step 5: Resolve all threads

After responding to every comment, resolve each thread via GraphQL:

```bash
gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "THREAD_NODE_ID"}) { thread { isResolved } } }'
```

Get thread node IDs from:

```bash
gh api graphql -f query='{ repository(owner: "OWNER", name: "REPO") { pullRequest(number: PR_NUM) { reviewThreads(first: 50) { nodes { id isResolved comments(first: 1) { nodes { body } } } } } } }'
```

Only resolve threads you have actually responded to.

## Rules

- **Never implement blindly.** Verify every suggestion against the codebase before touching code.
- **Never thank the reviewer.** State the fix or state the pushback. Actions speak.
- **Never say "great point" or "you're right."** Just fix it or challenge it.
- **Always resolve threads.** Responding without resolving leaves the PR in limbo.
- **Push back when warranted.** A wrong suggestion implemented is worse than a wrong suggestion challenged.
