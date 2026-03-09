---
name: resolve-pr-comments
description: >
  Structured workflow for handling PR review feedback that most people
  get wrong: fetches all comments via GitHub API and GraphQL, critically
  evaluates each one BEFORE making changes (classifying as FIX, PUSHBACK,
  or CLARIFY), challenges incorrect suggestions with evidence instead of
  blindly implementing, replies in-thread, resolves threads, and commits
  atomically. This skill provides a disciplined methodology that prevents
  wasted effort from applying wrong suggestions. ALWAYS consult this
  skill when the user wants to deal with PR review comments, changes
  requested, reviewer feedback, Copilot/CodeRabbit suggestions, comment
  threads, or any unresolved review on a pull request. Use it even for
  seemingly simple cases — the evaluation framework catches mistakes that
  naive implementation misses. Invoke with /resolve-pr-comments or
  /resolve-pr-comments <PR-number>.
allowed-tools: Bash(gh *), Bash(git *), Read, Glob, Grep, Edit, Write, WebSearch, WebFetch
---

# /resolve-pr-comments — PR Review Comment Handler

Work through every review comment on a PR: evaluate each one critically, fix what's right, push back on what's wrong, and resolve all threads.

## Usage

```
/resolve-pr-comments              # uses the PR for the current branch
/resolve-pr-comments <number>     # targets a specific PR
```

## Process

### Step 1: Find the PR and fetch comments

If a PR number was provided, use it directly. Otherwise, find the PR for the current branch:

```bash
PR_JSON=$(gh pr view --json number,url,headRefName,baseRefName,reviewDecision)
PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number')
PR_URL=$(echo "$PR_JSON" | jq -r '.url')
PR_BRANCH=$(echo "$PR_JSON" | jq -r '.headRefName')
```

If no open PR exists for the current branch, say so and stop.

If `reviewDecision` is `APPROVED` with no unresolved threads, report that the PR is already approved and stop — don't go looking for problems.

Fetch the repo identifier once:

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

Then fetch all review feedback in two calls:

```bash
# Line-level comments (code-specific feedback)
LINE_COMMENTS=$(gh api "repos/$REPO/pulls/$PR_NUMBER/comments" \
  --jq '.[] | {id, node_id, path, line: .original_line, diff_hunk: .diff_hunk, body: .body, user: .user.login, in_reply_to_id}')

# Top-level review bodies (summary feedback, often accompanies CHANGES_REQUESTED)
REVIEW_BODIES=$(gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" \
  --jq '.[] | select(.body != "" and .body != null) | {id, node_id, body, user: .user.login, state}')
```

Group line-level comments into threads using `in_reply_to_id` — only the root comment (where `in_reply_to_id` is null) represents a unique piece of feedback. Reply comments are part of an existing conversation.

If there are no comments to address, report that and stop.

### Step 2: Fetch unresolved threads

Get thread resolution status to focus only on unresolved feedback:

```bash
OWNER=$(echo "$REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO" | cut -d/ -f2)

THREADS=$(gh api graphql -f query='
  query {
    repository(owner: "'"$OWNER"'", name: "'"$REPO_NAME"'") {
      pullRequest(number: '"$PR_NUMBER"') {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 1) {
              nodes { body databaseId }
            }
          }
        }
      }
    }
  }
')
```

Cross-reference with the line-level comments to build a mapping of comment ID → thread node ID. Skip threads that are already resolved — they don't need attention.

### Step 3: Evaluate each comment

This is the critical step. Before touching any code, evaluate every unresolved comment independently.

For each comment:

1. **Understand the request.** What specific change is being suggested? What's the reviewer's reasoning?

2. **Read the code.** Open the file at the referenced line. Read enough surrounding context to understand the intent — not just the line, but the function, the module's purpose, the pattern being followed.

3. **Check project conventions.** Does the suggestion align with or contradict the project's CLAUDE.md, established patterns, or architectural decisions?

4. **Assess technical correctness.** Is the reviewer right about how the code works? Are they referencing current APIs/patterns, or outdated ones? Would the change introduce a regression?

5. **Consider the source.** Human reviewers generally have project context but may miss details. Automated reviewers (GitHub Copilot, CodeRabbit, etc.) apply generic rules that may conflict with project-specific conventions — they deserve extra scrutiny.

6. **Classify the comment:**

| Verdict | Meaning |
|---------|---------|
| **FIX** | Reviewer is correct — apply the change |
| **PUSHBACK** | Reviewer is wrong or the suggestion doesn't fit — reply with evidence |
| **CLARIFY** | Ambiguous — ask the reviewer a specific question |

When in doubt between FIX and PUSHBACK, check the code one more time. A wrong fix applied is worse than a correct challenge issued.

### Step 4: Act on each comment

Work through all classified comments:

**FIX comments:** Make the change. Keep the fix minimal and focused on what the reviewer asked for — don't refactor the neighborhood.

**PUSHBACK comments:** Reply in the thread with technical reasoning. Reference specific code, patterns, docs, or conventions. Be direct and evidence-based — no filler, no apologies, no "great catch but..."

**CLARIFY comments:** Reply with a specific question that will unblock you. Not "can you elaborate?" but "did you mean X or Y? The current approach does Z because..."

Reply to comments in their thread:

```bash
# For line-level comments, reply in the review comment thread
gh api "repos/$REPO/pulls/$PR_NUMBER/comments/$COMMENT_ID/replies" \
  -f body="Your response here"

# For top-level review bodies, reply as a PR comment
gh pr comment $PR_NUMBER --body "Your response here"
```

### Step 5: Commit and push fixes

If any code changes were made:

1. Review your diff — does each change correspond to a reviewer comment?
2. Commit atomically — one commit per independent concern, or one commit if all fixes are related.
3. Push to the PR branch.

```bash
git add <specific-files>
git commit -m "fix: address review feedback

- <brief description of each fix>"
git push origin $PR_BRANCH
```

If no code changes were made (all comments were pushbacks or clarifications), skip this step.

### Step 6: Resolve threads

Resolve every thread where you took action (FIX or PUSHBACK). Leave CLARIFY threads open — they need a response before they can be resolved.

```bash
gh api graphql -f query='
  mutation {
    resolveReviewThread(input: {threadId: "THREAD_NODE_ID"}) {
      thread { isResolved }
    }
  }
'
```

Only resolve threads you have actually responded to.

### Step 7: Report

Summarize what was done:

```
PR #<number>: <X> comments addressed
- Fixed: <N> (list brief descriptions)
- Pushed back: <N> (list brief descriptions)
- Clarified: <N> (list brief descriptions)
```

Include the PR URL so the user can review.

## Rules

- **Evaluate before implementing.** Read the code and understand the context before applying any suggestion. Blind implementation wastes everyone's time.
- **Push back when warranted.** A wrong suggestion implemented is worse than a wrong suggestion challenged. If the reviewer is incorrect, say so with evidence.
- **No flattery.** Don't thank the reviewer, say "great point," or "you're right." State the fix or state the pushback.
- **Always resolve threads.** Responding without resolving leaves the PR in limbo. The only exception is CLARIFY threads that need a response back.
- **Respect commit conventions.** Follow the project's CLAUDE.md for commit message format and atomic commit rules.
- **Don't expand scope.** Only address what reviewers commented on. Don't refactor nearby code, add comments to unchanged lines, or fix unrelated issues.
- **Read before writing.** Never modify a file you haven't read in this session.
