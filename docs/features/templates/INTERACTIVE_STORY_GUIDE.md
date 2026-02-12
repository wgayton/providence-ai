# Interactive Story Creation Guide

**Purpose:** This guide provides Claude Code with a structured question flow to help you create complete user stories through conversation.

---

## When to Use This Guide

**User says:**
- "Help me create a story"
- "Guide me through writing a story"
- "Ask me questions to create a story"
- "I have a feature idea, can you help me document it?"

**Claude Code should:**
1. Reference this guide
2. Ask questions in the order defined below
3. Capture responses
4. Generate complete story file using the template

---

## Question Flow

### Phase 1: Story Foundation (Required)

**Q1: Feature Name & Story ID**
```
What would you like to call this feature? Also, do you have a story ID
(e.g., PROV-123), or should I generate one?
```
**Capture:** Story ID, Feature Name

---

**Q2: User Story Components**
```
Let's build the user story. I need three things:

1. Who is the actor/role? (e.g., "Tenant Administrator", "Project Manager",
   "Resource Allocator", "Finance Controller")

2. What capability or action do they want? (e.g., "create a project",
   "allocate resources to a project", "transfer funds between accounts")

3. Why? What's the business value or outcome? (e.g., "so that I can track
   work across teams", "so that resource utilization is visible")
```
**Capture:** Actor, Capability, Business Value

---

**Q3: Acceptance Criteria**
```
What are the must-have acceptance criteria? List at least 3 things that
MUST be true for this story to be considered complete.

Examples:
- User can create a project with name, description, and budget
- System validates budget is positive
- Project appears in project list immediately after creation
- Email notification sent to project owner

What are your must-have criteria?
```
**Capture:** Must-have criteria (minimum 3)

---

**Q4: Optional Criteria (Nice to Have)**
```
Are there any "nice to have" features that would be valuable but aren't
required for the first version?

Examples:
- Project templates for quick setup
- Bulk project import from CSV
- Custom project fields

What are your nice-to-have criteria? (or say "none")
```
**Capture:** Should-have criteria (optional)

---

**Q5: Out of Scope**
```
To keep the story focused, what's explicitly OUT OF SCOPE? What won't
be included?

Examples:
- Project archiving (future story)
- Project templates (defer to later)
- Advanced reporting (separate feature)

What's out of scope? (or say "nothing specific")
```
**Capture:** Out-of-scope items

---

**Q6: Business Context**
```
Help me understand the business context:

1. What problem does this solve? Why does it matter?
2. Who are the primary users? (e.g., Tenant Admins, Project Managers)
3. Who are secondary users, if any?
4. How will you measure success? (e.g., "reduce manual data entry by 50%",
   "improve project creation time to under 30 seconds")
```
**Capture:** Problem statement, primary users, secondary users, success metrics

---

### ✅ Checkpoint: Tier 1 Complete

At this point, say:
```
Great! I have enough information to create a basic story (Tier 1).

Would you like me to:
1. Generate the story now with just these essentials? (Recommended for early-stage ideas)
2. Continue with architecture and implementation details? (Recommended if ready to implement)
```

**If user chooses 1:** Generate story with Tier 1 complete, Tier 2/3 collapsed
**If user chooses 2:** Continue to Phase 2

---

### Phase 2: Architecture & Implementation (Optional)

**Q7: Affected Domains**
```
Which parts of the Providence AI system does this feature affect?

Select all that apply:
- [ ] Project Management
- [ ] Resource Management
- [ ] Fund Management
- [ ] Human Management
- [ ] Tenant Administration
- [ ] Other: _____
```
**Capture:** Affected domains

---

**Q8: Integration Points**
```
How does this feature integrate with the rest of the system?

1. What REST endpoints will be exposed? (e.g., POST /api/v1/projects)
2. What gRPC services will be exposed? (or say "none")
3. What domain events will be emitted? (e.g., ProjectCreated, ProjectUpdated)
4. What events will this feature consume? (or say "none")
```
**Capture:** API endpoints, events emitted, events consumed

---

**Q9: Database Schema**
```
What data needs to be stored?

1. What's the main entity/aggregate? (e.g., "Project", "Resource", "Transfer")
2. What are the key fields? (e.g., "name, description, budget, owner_id, status")
3. Are there any foreign keys or relationships? (e.g., "belongs to tenant, has many allocations")
```
**Capture:** Entity name, key fields, relationships

---

**Q10: Security & Authorization**
```
Who should be allowed to perform this action?

Examples:
- Only TENANT_ADMIN can create projects
- PROJECT_MANAGER can create and update their own projects
- VIEWER can only read projects

What roles are required?
```
**Capture:** Required roles, authorization rules

---

**Q11: Testing Scenarios**
```
Let's define the critical test scenarios:

1. Happy path: Describe the ideal successful flow
2. Validation: What invalid inputs should be rejected?
3. Cross-tenant isolation: How will we verify a user can't access
   another tenant's data?
4. Other scenarios: Any edge cases or special conditions?
```
**Capture:** Test scenarios

---

### ✅ Checkpoint: Tier 2 Complete

At this point, say:
```
Excellent! I now have enough detail to create a story with architecture
and implementation guidance (Tier 2).

Would you like me to:
1. Generate the story now? (Recommended)
2. Add production readiness details? (Only if you want to fill in
   observability and deployment details now)
```

**If user chooses 1:** Generate story with Tier 1 + Tier 2 complete
**If user chooses 2:** Continue to Phase 3

---

### Phase 3: Production Readiness (Optional)

**Q12: Observability**
```
Let's define observability requirements:

1. What key metrics should be tracked? (e.g., "project.created.count",
   "project.create.duration")
2. What log messages are critical? (e.g., "Project {id} created by user {userId}")
3. Are there any alerts or monitoring requirements?
```
**Capture:** Metrics, log messages, alerts

---

**Q13: Error Handling & Resilience**
```
How should the system handle failures?

1. Are there any external service calls? If so, what's the fallback behavior?
2. What's the retry strategy for transient failures?
3. What errors should be logged vs. metrics vs. alerts?
```
**Capture:** Error handling strategy, fallbacks, retry logic

---

**Q14: Performance & Scale**
```
What are the performance requirements?

1. Expected request volume? (e.g., "10 projects created per day per tenant")
2. Response time requirements? (e.g., "< 500ms p99")
3. Any caching requirements?
```
**Capture:** Volume, latency, caching

---

### ✅ Final: Generate Complete Story

At this point, say:
```
Perfect! I have all the information needed to create a comprehensive
story with full production readiness details (Tier 3).

I'll generate the story file now at:
docs/features/{feature-name}/{story-id}-{description}.md

Generating...
```

**Then:** Create the complete story file using `AGILE_STORY_TEMPLATE.md`

---

## Response Handling

### User Provides Partial Information
If the user gives incomplete answers:
```
Thanks! Just to clarify [specific question]. Could you provide a bit
more detail on [missing information]?
```

### User Says "Skip" or "I don't know"
```
No problem! I'll leave that section for you to fill in later. The template
has placeholder text you can update when you have more information.
```

### User Wants to Go Back
```
Of course! Let me capture what we have so far, and you can tell me what
you'd like to change.
```

---

## Story Generation

### After Gathering Responses

**1. Create File Path**
```
docs/features/{feature-name}/{story-id}-{description}.md
```

**2. Fill Template**
- Copy `AGILE_STORY_TEMPLATE.md`
- Replace placeholders with captured information
- Leave uncompleted sections with placeholder text
- Set appropriate status (usually "Draft" or "Ready")

**3. Confirm with User**
```
✅ Story created at: docs/features/{feature}/{story-id}-{description}.md

Summary:
- Story ID: {id}
- Feature: {name}
- Actor: {actor}
- Capability: {capability}
- Must-have criteria: {count}
- Status: {status}

Would you like me to:
1. Show you the generated story
2. Commit it to git
3. Make any changes first
```

---

## Example Interaction

**User:** "Help me create a story for project creation"

**Claude:**
```
Great! I'll guide you through creating a story for project creation.

Q1: What would you like to call this feature? Also, do you have a story ID
(e.g., PROV-123), or should I generate one?
```

**User:** "Call it 'Create Project' and use PROV-001"

**Claude:**
```
Perfect! Story ID: PROV-001, Feature: Create Project

Q2: Let's build the user story. I need three things:
1. Who is the actor/role?
2. What capability or action do they want?
3. Why? What's the business value or outcome?
```

**User:** "Tenant Administrator wants to create projects so they can organize work"

**Claude:**
```
Excellent!

As a Tenant Administrator
I want to create projects
So that I can organize work across my team

Q3: What are the must-have acceptance criteria? List at least 3 things that
MUST be true for this story to be considered complete.
```

[... continues through all questions ...]

---

## Tips for Claude Code

**Be Conversational:**
- Use natural language
- Ask follow-up questions if needed
- Provide examples to guide responses

**Be Flexible:**
- User might provide more or less detail than expected
- Adapt question flow based on responses
- Allow skipping optional questions

**Be Helpful:**
- Offer examples for each question
- Explain why the information is needed
- Link to documentation if user seems confused

**Be Efficient:**
- Don't ask redundant questions
- Combine related questions if user provides detailed answers
- Offer to skip Tier 2/3 if user just needs basic story

---

**Version:** 1.0.0
**Last Updated:** 2026-02-12
