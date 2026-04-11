---
name: advisor-strategy
description: Pair a smaller executor model with Opus advisor for cost-effective agentic intelligence. Use when building agents that need near-Opus reasoning but Sonnet/Haiku cost. Use when your agent has explicit decision points where it needs guidance from a stronger model.
---

# Advisor Strategy

⚠️ **In Development** — Code Review domain is production-ready. Research domain framework is complete but needs eval dataset tuning.

## Overview

The advisor strategy pairs a smaller, cost-effective executor model (Sonnet or Haiku) with Opus as an advisor. The executor runs your task end-to-end—calling tools, reading results, iterating—while Opus consults only at pre-defined checkpoints where the executor shouldn't make decisions alone.

Unlike patterns where the executor "decides when to escalate," this approach **explicitly marks which decisions need advisor approval**. The executor recognizes these checkpoints in its system prompt and calls the advisor before proceeding.

**Key metric:** Sonnet + Opus advisor shows ~2.7 point gains on SWE-bench with 11.9% lower cost than Sonnet alone.

## When to Use

- **You have explicit decision points:** "Before merging code, get approval" or "If findings conflict, escalate"
- **Cost matters but reasoning quality is critical:** You need better-than-Sonnet for specific decisions, not all decisions
- **Tool-heavy workflows:** Most work is tools + context (cheap), decision-making is rare (worth escalating)
- **You can define clear escalation triggers:** Not "when unsure" (vague), but "when X happens, escalate"

**When NOT to use:**
- Tasks where reasoning is distributed throughout (just use Opus)
- Real-time, latency-critical workflows (extra round-trip adds delay)
- You can't identify explicit decision points (too vague)
- Advisor calls would exceed executor calls (you're using advisor for everything)

## Which Strategy for Your Task?

**Pick based on task type, not cost:**

| Task Type | Best Strategy | Why | Escalation Trigger |
|-----------|---------------|-----|-------------------|
| **Code review, approval** | Executor + Advisor | Executor flags issues, advisor approves/rejects. | Before merge or on high-risk changes |
| **Research, synthesis** | Executor + Advisor | Executor gathers data, advisor interprets patterns. | When data sources conflict or findings unclear |

## Implementation (Generic)

### 1. Define Explicit Checkpoints (Use `spec-driven-development`)

**Before writing code, map out where advisor will be consulted:**

```
Task: [YOUR TASK]
├─ Executor: [Phase 1: gather/prepare]
├─ Checkpoint A: [Decision point]
│  └─ Condition: [Observable trigger]
├─ Executor: [Phase 2: act/process]
├─ Checkpoint B: [Decision point]
│  └─ Condition: [Observable trigger]
└─ Return result
```

**What makes a good checkpoint:**
- Observable: "If X condition is true, escalate" (not "if unsure")
- Bounded: Set max escalations per checkpoint (e.g., "max 2 times per task")
- Executor-recognizable: Executor can detect the condition in its own work
- Valuable: Advisor input actually changes the outcome

### 2. Design the Contract (Use `api-and-interface-design`)

**Executor system prompt template:**

```
You are a [DOMAIN] agent. Your role:
1. Use tools to gather information and make safe changes
2. At these CHECKPOINTS, ALWAYS consult the advisor before proceeding:
   - CHECKPOINT A: Before [decision], if [condition]
   - CHECKPOINT B: Before [decision], always
   - CHECKPOINT C: If [condition], before [decision]
3. When calling the advisor, provide:
   - Current status (what you've learned so far)
   - Options you're considering
   - Your confidence level
4. Implement the advisor's guidance exactly as stated
5. If advisor says "stop", stop and report the blockers

DO NOT escalate outside these checkpoints.
DO NOT ignore advisor guidance.
```

**Advisor system prompt template:**

```
You are reviewing an executor's work on [DOMAIN] task. You NEVER modify code or call tools.

Your role at each checkpoint:
- CHECKPOINT A: [Validation task]
- CHECKPOINT B: [Review task]
- CHECKPOINT C: [Strategy task]

Response format:
- Return one of: "approved, proceed" | "objection: [reason], try [alternative]" | "stop: [blocker]"
- Keep guidance to 2–3 sentences max
- If executor is right, say "approved"
```

### 3. Implement Incrementally (Use `incremental-implementation`)

**Slice 1: Executor alone, no advisor**
```python
executor_alone_accuracy = run_eval(executor_only=True, num_tasks=50)
print(f"Executor alone: {executor_alone_accuracy:.1%} accuracy")
# Goal: Baseline to measure improvement against
```

**Slice 2: Add first checkpoint**
```python
executor_advisor_partial = run_eval(
    checkpoints=["A"],
    max_uses=1,
    num_tasks=50
)
accuracy_delta = executor_advisor_partial - executor_alone_accuracy
if accuracy_delta < 0.02:
    print("Checkpoint A not helping. Remove it.")
else:
    print(f"Checkpoint A valuable: +{accuracy_delta:.1%}")
```

**Slice 3: Add all checkpoints**
```python
executor_advisor_full = run_eval(
    checkpoints=["A", "B", "C"],
    max_uses=3,
    num_tasks=100
)
```

### 4. Evaluate Production-Ready (Use `test-driven-development` + `performance-optimization`)

**Core evaluation script (runnable):**

```python
import json
from anthropic import Anthropic
from typing import Dict, List

client = Anthropic()

def evaluate_agent(tasks: List[Dict], use_advisor: bool, checkpoint_config: Dict = None) -> Dict:
    """Evaluate agent on a set of tasks."""
    results = []
    
    for task in tasks:
        tools_list = [
            # Add your domain-specific tools here
        ]
        
        if use_advisor:
            tools_list.insert(0, {
                "type": "advisor_20260301",
                "name": "advisor",
                "model": "claude-opus-4-6",
                "max_uses": checkpoint_config.get("max_uses", 3),
            })
        
        response = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=4096,
            tools=tools_list,
            system=build_system_prompt(task["domain"], checkpoint_config if use_advisor else None),
            messages=[{"role": "user", "content": task["input"]}]
        )
        
        # Extract metrics based on domain
        success = evaluate_task_success(task, response)
        
        results.append({
            "task_id": task["id"],
            "success": success,
            "executor_tokens": response.usage.input_tokens,
            "executor_output_tokens": response.usage.output_tokens,
            "advisor_tokens": getattr(response.usage, 'advisor_input_tokens', 0),
            "advisor_output_tokens": getattr(response.usage, 'advisor_output_tokens', 0),
            "advisor_used": getattr(response.usage, 'advisor_input_tokens', 0) > 0,
        })
    
    # Aggregate metrics
    accuracy = sum(1 for r in results if r["success"]) / len(results)
    avg_executor_cost = sum(
        r["executor_tokens"] * 0.003 + r["executor_output_tokens"] * 0.006
        for r in results
    ) / len(results)
    avg_advisor_cost = sum(
        r["advisor_tokens"] * 0.015 + r["advisor_output_tokens"] * 0.060
        for r in results
    ) / len(results) if use_advisor else 0
    
    return {
        "accuracy": accuracy,
        "executor_cost": avg_executor_cost,
        "advisor_cost": avg_advisor_cost,
        "total_cost": avg_executor_cost + avg_advisor_cost,
        "advisor_calls": sum(1 for r in results if r["advisor_used"]),
        "advisor_calls_per_task": sum(1 for r in results if r["advisor_used"]) / len(results),
    }

# Run evaluations
print("=== EXECUTOR ALONE ===")
executor_only = evaluate_agent(test_tasks, use_advisor=False)
print(f"Accuracy: {executor_only['accuracy']:.1%}")
print(f"Cost per task: ${executor_only['total_cost']:.3f}")

print("\n=== EXECUTOR + ADVISOR ===")
checkpoint_config = {
    "max_uses": 2,
    "checkpoints": ["before_major_decision", "after_failed_attempt"]
}
with_advisor = evaluate_agent(test_tasks, use_advisor=True, checkpoint_config=checkpoint_config)
print(f"Accuracy: {with_advisor['accuracy']:.1%}")
print(f"Cost per task: ${with_advisor['total_cost']:.3f}")
print(f"Advisor calls per task: {with_advisor['advisor_calls_per_task']:.2f}")

# Decision
print("\n=== DECISION ===")
accuracy_gain = with_advisor['accuracy'] - executor_only['accuracy']
cost_premium = (with_advisor['total_cost'] / executor_only['total_cost'] - 1)
print(f"Accuracy gain: {accuracy_gain:+.1%}")
print(f"Cost premium: {cost_premium:+.1%}")

if accuracy_gain >= 0.02 and cost_premium <= 0.5:
    print("✓ DEPLOY WITH ADVISOR")
elif accuracy_gain < 0.01:
    print("✗ REMOVE ADVISOR (not helping)")
else:
    print("? INVESTIGATE (gains exist but expensive)")
```

---

## Domain-Specific Reference Implementations

### Domain 1: Code Review Agent

**Status:** Production-ready

**Tools:**

```python
tools = [
    {
        "type": "function",
        "name": "read_file",
        "description": "Read file content to review code",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string"}
            }
        }
    },
    {
        "type": "function",
        "name": "get_git_diff",
        "description": "Get the diff for a specific change",
        "input_schema": {
            "type": "object",
            "properties": {
                "commit_hash": {"type": "string"},
                "file_path": {"type": "string", "description": "optional, if empty shows all files"}
            }
        }
    },
    {
        "type": "function",
        "name": "check_tests",
        "description": "Check if tests pass for this change",
        "input_schema": {
            "type": "object",
            "properties": {
                "commit_hash": {"type": "string"}
            }
        }
    },
    {
        "type": "function",
        "name": "analyze_security",
        "description": "Scan code for security issues",
        "input_schema": {
            "type": "object",
            "properties": {
                "code": {"type": "string"}
            }
        }
    },
    {
        "type": "function",
        "name": "check_performance",
        "description": "Assess performance implications",
        "input_schema": {
            "type": "object",
            "properties": {
                "code": {"type": "string"},
                "context": {"type": "string", "description": "what part of system this affects"}
            }
        }
    },
    {
        "type": "function",
        "name": "draft_review",
        "description": "Draft a code review comment",
        "input_schema": {
            "type": "object",
            "properties": {
                "issues": {"type": "array", "items": {"type": "string"}},
                "tone": {"type": "string", "enum": ["blocking", "suggest", "approve"]}
            }
        }
    }
]
```

**Checkpoints (Specific, Observable):**

```
CHECKPOINT A: Security-sensitive code
  Condition: analyze_security returns any issues OR changes touch auth/crypto/database
  What executor provides: code diff, security scan results, risk assessment
  What advisor does: validate findings, approve or suggest safe alternatives
  Max uses: 2 per change
  
CHECKPOINT B: Performance-critical code  
  Condition: check_performance flags degradation OR changes touch hot paths
  What executor provides: performance analysis, affected areas, proposed optimization
  What advisor does: validate optimization approach, approve or suggest better strategy
  Max uses: 1 per change
  
CHECKPOINT C: Large architectural changes
  Condition: changes affect 5+ files OR modify core module structure
  What executor provides: scope analysis, impact assessment, design rationale
  What advisor does: validate architecture decision, approve or suggest alternative
  Max uses: 1 per change
```

**Executor system prompt:**

```
You are a code review agent. Your task: Review a code change and recommend approval or rejection.

Tools: read_file, get_git_diff, check_tests, analyze_security, check_performance, draft_review

Workflow:
1. Get the diff and read affected files
2. Run tests and security scan
3. Assess performance impact

CHECKPOINTS (you MUST escalate at these exact conditions):

CHECKPOINT A: Security-sensitive code
  Condition: analyze_security returns issues OR changes touch auth.py, crypto/, database/
  Provide: "Files: [list]. Security issues: [findings]. Risk level: [low/medium/high]. Recommend: [block/approve]"
  
CHECKPOINT B: Performance-critical code
  Condition: check_performance shows degradation OR changes hit hot paths
  Provide: "Performance impact: [analysis]. Affected: [areas]. Optimization: [your idea]. Approve?: [yes/no]"
  
CHECKPOINT C: Large architectural changes
  Condition: changes affect 5+ files OR modify core/ directory
  Provide: "Scope: [summary]. Impact: [affected systems]. Design: [your analysis]. Approve?: [yes/no]"

Otherwise:
  - Review code for style, logic, tests
  - Draft review with tone: blocking (must fix), suggest (nice to have), or approve
  - Don't escalate for minor issues
```

**Advisor system prompt:**

```
You are a senior code reviewer. Review the executor's code review.

Checkpoints:
- CHECKPOINT A (security): Are the security concerns valid? Approve or suggest safer alternative.
- CHECKPOINT B (performance): Is performance analysis correct? Approve approach or suggest optimization.
- CHECKPOINT C (architecture): Is design decision sound? Approve or suggest architectural alternative.

Respond with exactly one of:
- "approved, safe to merge" — executor's review is correct
- "objection: [specific concern], suggest [alternative]" — executor missed something or proposal is wrong
- "block: [reason]" — this change should not merge
```

**Sample eval tasks:**

```python
code_review_tasks = [
    {
        "id": "sql_injection_risk",
        "domain": "code_review",
        "description": "Review SQL query change with injection risk",
        "diff": "User input passed directly to SQL query without parameterization",
        "files_changed": ["src/database/queries.py"],
        "security_scan_result": "SQL injection vulnerability",
        "expected_escalations": ["CHECKPOINT A (security issue)"],
        "expected_outcome": "Block merge, request parameterized query",
        "success_criteria": "Advisor blocks change due to security"
    },
    {
        "id": "simple_refactor",
        "domain": "code_review",
        "description": "Review simple refactoring",
        "diff": "Extract method, no logic changes",
        "files_changed": ["src/utils/helpers.py"],
        "security_scan_result": "None",
        "performance_impact": "None",
        "tests": "All passing",
        "expected_escalations": [],
        "expected_outcome": "Approve merge",
        "success_criteria": "Auto-approve without escalation"
    },
    {
        "id": "caching_optimization",
        "domain": "code_review",
        "description": "Review caching layer addition to hot path",
        "diff": "Add Redis caching to user lookup",
        "files_changed": ["src/auth/user_lookup.py", "src/cache/redis_client.py", "tests/test_user_lookup.py"],
        "performance_impact": "50% latency reduction, adds dependency",
        "tests": "All passing + new cache tests",
        "expected_escalations": ["CHECKPOINT B (performance change)"],
        "expected_outcome": "Approve with verification of cache invalidation",
        "success_criteria": "Advisor validates caching strategy"
    },
    {
        "id": "large_refactor",
        "domain": "code_review",
        "description": "Review large architectural change",
        "diff": "Migrate from monolithic auth to microservice",
        "files_changed": ["src/auth/", "src/middleware/", "src/api/", "tests/", "docs/"],
        "scope": "7 files, core architecture",
        "expected_escalations": ["CHECKPOINT C (architectural change)"],
        "expected_outcome": "Advisor reviews design, might request additional tests",
        "success_criteria": "Advisor validates architecture decision"
    }
]
```

**Monitoring (domain-specific):**

```python
# Per review
review_metrics = {
    "security_issues_found": count,
    "performance_issues_found": count,
    "advisor_escalations": ticket.advisor_calls,
    "approval_decision": "blocked/approved",
    "review_time_minutes": (completion - start).minutes
}

# Weekly aggregate
weekly_metrics = {
    "reviews_completed": count,
    "approval_rate": approved / total,  # Target: 60-80%
    "block_rate": blocked / total,  # Target: 5-15%
    "advisor_escalation_rate": escalated / total,  # Target: <20%
    "avg_review_time": mean(review_times),  # Target: <10 min
    "security_escalation_rate": security_escalations / total,  # Target: >80% of security issues caught
    "false_blocks": blocked_but_ok / blocked,  # Target: <5%
    "missed_issues": issues_in_prod_that_were_approved / approved,  # Target: <1%
}

# Alerts
if weekly_metrics["block_rate"] > 0.20:
    alert("Too many blocks. Executor may be too strict.")
if weekly_metrics["security_escalation_rate"] < 0.70:
    alert("Missing security issues. Escalate more or improve scanner.")
if weekly_metrics["missed_issues"] > 0.02:
    alert("Issues slipped through. Advisor approval standards too low.")
```

---

### Domain 2: Research Agent (Synthesis & Analysis)

**Status:** Framework complete, needs eval dataset tuning

**Tools:**

```python
tools = [
    {
        "type": "function",
        "name": "search_sources",
        "description": "Search academic/web sources",
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
                "num_sources": {"type": "integer"}
            }
        }
    },
    {
        "type": "function",
        "name": "fetch_source",
        "description": "Read full source content",
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string"}
            }
        }
    },
    {
        "type": "function",
        "name": "extract_key_findings",
        "description": "Extract key data/findings from source",
        "input_schema": {
            "type": "object",
            "properties": {
                "content": {"type": "string"}
            }
        }
    },
    {
        "type": "function",
        "name": "detect_contradictions",
        "description": "Check if findings contradict previous sources",
        "input_schema": {
            "type": "object",
            "properties": {
                "new_finding": {"type": "string"},
                "previous_findings": {"type": "array"}
            }
        }
    },
    {
        "type": "function",
        "name": "synthesize_analysis",
        "description": "Create synthesis/conclusion from findings",
        "input_schema": {
            "type": "object",
            "properties": {
                "findings": {"type": "array"},
                "tone": {"type": "string"}
            }
        }
    }
]
```

**Checkpoints:**

```
CHECKPOINT A: If findings contradict each other
  Condition: detect_contradictions returns conflict
  Executor: Explains the contradiction and reconciliation attempt
  Advisor: Validates handling or suggests alternative interpretation
  
CHECKPOINT B: If synthesis confidence is low
  Condition: synthesize_analysis returns confidence < 0.7
  Executor: Proposes conclusion anyway with caveats
  Advisor: Approves conclusion or suggests more research
  
CHECKPOINT C: If findings are from unreliable sources
  Condition: Source credibility assessment comes back low
  Executor: Proposes how to handle unreliable data
  Advisor: Advises on weighting or exclusion
```

**Executor system prompt:**

```
You are a research analysis agent. Your task: Answer a research question.

Tools: search_sources, fetch_source, extract_key_findings, detect_contradictions, synthesize_analysis

CHECKPOINTS:
1. CHECKPOINT A: If findings from different sources contradict
   Provide: the contradiction, your analysis, proposed reconciliation
   
2. CHECKPOINT B: If your synthesis confidence is < 70%
   Provide: findings collected, why confidence is low, proposed caveats
   
3. CHECKPOINT C: If some sources are low-credibility
   Provide: which sources, why low-credibility, how you'd weight them

Otherwise: Search, extract findings, synthesize without escalating.
```

**Advisor system prompt:**

```
You are reviewing a research agent's analysis.

Checkpoints:
- CHECKPOINT A: Is the contradiction analysis sound? Approve or provide better interpretation.
- CHECKPOINT B: Are the caveats appropriate? Approve synthesis or suggest more research.
- CHECKPOINT C: Should unreliable sources be excluded? Approve weighting strategy or revise.

Response: "approved" | "recommendation: [guidance]" | "research_needed: [areas]"
```

---

## Common Failure Modes

### 🔴 "Executor escalates on every decision"

**Code review:**
```
Root cause: Checkpoints too broad ("if any security issue" = everything)
Fix: Be specific: "Only escalate if analyze_security returns CRITICAL or if auth.py touched"
```

**Research:**
```
Root cause: Executor over-escalates on uncertainty
Fix: Set confidence threshold: "Only escalate if < 0.6, not on every hedge"
```

---

### 🔴 "Advisor approves bad decisions"

**Code review:**
```
Root cause: Executor didn't provide enough context (diff + security scan + test results)
Fix: Require all three: "Provide: diff, security_scan, test_results, your_recommendation"
```

**Research:**
```
Root cause: Advisor didn't catch unreliable source
Fix: Require: "Source credibility: [assessment]. Why this source matters: [reasoning]"
```

---

### 🔴 "Executor ignores advisor guidance"

**Code review:**
```
Root cause: Executor sees objection but proceeds anyway
Fix: Enforce: "If advisor says block, flag PR for human. Don't override."
```

**Research:**
```
Root cause: Executor disagrees with advisor's recommendation
Fix: System prompt: "If advisor says needs more research, search more sources"
```

---

## Production Readiness Checklist

Before deploying to production:

### All Domains
- [ ] Checkpoints are explicit (not vague)
- [ ] System prompts are domain-tested
- [ ] Evaluation script runs on 50+ representative tasks
- [ ] Accuracy gain ≥ 2% OR clear business value
- [ ] Cost premium ≤ 50% OR accuracy gain justifies it
- [ ] Failure mode runbook documented
- [ ] Monitoring dashboards set up
- [ ] Advisor call patterns reviewed (< 2 calls/task on avg)

### Code Review Agents
- [ ] Security escalations catch 80%+ of real security issues
- [ ] Test suite passes with advisor enabled
- [ ] False blocks < 5% (blocking changes that are actually safe)
- [ ] Missed issues < 1% (issues that slip through approval)

### Research Agents
- [ ] Synthesis accuracy expert-verified > 75%
- [ ] Source credibility assessment validated
- [ ] Contradiction handling tested on conflicting-study questions
- [ ] Citation accuracy > 95%

---

## Verification

A task is complete when:

1. **Checkpoints are explicit:** 2–3 decision points with clear, observable conditions
2. **System prompts tested:** Real tasks run, advisor behaves as designed
3. **Evaluation shows ROI:** Accuracy gain ≥ 2% and cost premium justified
4. **Domain-specific monitoring live:** Tracking domain metrics (not generic ones)
5. **Failure modes understood:** You can diagnose and fix each one
6. **Production checklist passed:** All items marked for your domain

**Example completion (Code Review):**
```
✓ Checkpoints: 3 defined (security, performance, architecture)
✓ System prompts: Tested on 50 real PRs
✓ Eval results: +3.2% security detection, +15% cost, ROI acceptable
✓ Monitoring: Tracking advisor_calls, block_rate, missed_issues
✓ Runbook: If false_blocks > 5%, tighten security threshold; if missed_issues rise, escalate more
✓ Production checklist: All items passed
→ Ready to deploy
```
