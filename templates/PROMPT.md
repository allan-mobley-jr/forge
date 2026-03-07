# My App Name

## What It Does

Describe your application in plain language. What problem does it solve? Who is it for?

## Pages & Features

List the main pages and features your app needs:

- **Home page** — what should it show?
- **Dashboard** — what data does the user see?
- **Settings** — what can the user configure?

## Design

Describe the look and feel:

- Modern and minimal? Bold and colorful? Corporate and clean?
- Any specific color palette or brand guidelines?
- Mobile-first? Desktop-focused? Both?

## Data & Integrations

What data does the app work with?

- Does it need a database? What kind of data is stored?
- Does it call external APIs? Which ones?
- Does it need authentication? What providers (Google, GitHub, email/password)?

## Anything Else

Any other details, constraints, or preferences:

- Must work offline?
- Needs real-time updates?
- Specific performance requirements?
- Accessibility needs?

> After you run `/plan`, Forge generates a `SPECIFICATION.md` from your prompt — a structured interpretation covering architecture, technology stack, design system, and constraints. This becomes the persistent reference document for the entire build.

---

## Tips for Writing a Good PROMPT.md

**Be specific about features.** The agent builds exactly what you describe. Vague prompts produce vague results.

**Good:**
> Dashboard page showing a bar chart of monthly revenue, a table of recent orders (last 10), and a card with total customers. Data comes from a REST API at /api/dashboard.

**Too vague:**
> Dashboard page with some charts and data.

**Include data relationships.** If your app has users, posts, and comments — say how they relate. The agent needs this to design the database schema and API routes.

**Specify auth requirements.** "Users can sign in with Google and GitHub" is much better than "needs authentication."

**Mention external services.** If you need Stripe, Resend, Supabase, or any third-party service, list them. The agent will set up the integration and flag any API keys you need to configure.

**Don't over-specify implementation details.** You don't need to say "use React Context for state management" — the agent's planning sub-agents will figure that out. Focus on *what* you want, not *how* to build it.

**Keep it to one page.** A PROMPT.md that's too long creates confusion. If your app is that complex, describe the MVP first — you can always add more issues later.
