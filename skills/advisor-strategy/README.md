# Advisor Strategy

Pair a smaller, cost-effective executor model (Sonnet/Haiku) with Opus as an advisor for near-Opus-level intelligence at executor cost.

## Domains

### ✅ Code Review (Production-Ready)
Review code changes with Sonnet as executor, Opus as advisor for security/performance/architecture decisions.

**Checkpoints:**
- Security-sensitive code (auth, crypto, database)
- Performance-critical changes (hot paths)
- Large architectural changes (5+ files, core modules)

**Use this when:**
- You need consistent code reviews at scale
- Security/performance decisions benefit from senior review
- False blocks (rejecting good code) hurt team velocity

**Start with:**
```python
from anthropic import Anthropic

client = Anthropic()

response = client.messages.create(
    model="claude-sonnet-4-6",
    tools=[
        {
            "type": "advisor_20260301",
            "name": "advisor",
            "model": "claude-opus-4-6",
            "max_uses": 2,  # Limit advisor calls
        },
        # ... your code review tools (read_file, git_diff, analyze_security, etc.)
    ],
    system="""You are a code review agent. Review the change.
    
CHECKPOINTS (escalate to advisor):
1. If code touches auth, crypto, or database → Advisor validates security
2. If performance impact detected → Advisor validates optimization
3. If architectural change affects 5+ files → Advisor validates design

Otherwise approve or block locally.""",
    messages=[{"role": "user", "content": "Review this PR: ..."}]
)
```

**Monitoring:**
- `advisor_calls_per_task` — should be < 0.5 (most reviews don't need escalation)
- `false_blocks` — % of blocked PRs that were actually safe (target: < 5%)
- `missed_issues` — security/performance issues that slipped through (target: < 1%)

---

### 🟡 Research (Framework Complete, In Progress)
Synthesis and analysis with contradiction handling, source credibility assessment, confidence thresholds.

**Status:** Framework is solid. Eval dataset tuning in progress. Expected: ~2 weeks.

---

## How It Works

1. **Executor (Sonnet)** runs the task end-to-end
2. **At checkpoints**, executor calls advisor for specific decisions
3. **Advisor (Opus)** validates, approves, or blocks
4. **Executor resumes** with advisor feedback

No round-trip overhead—everything happens in a single `/v1/messages` call with the `advisor_20260301` tool.

## Key Results

- **Code Review:** Catch 80%+ of real security/performance issues with <20% advisor escalations
- **Cost:** Executor cost + 15-20% for selective advisor consulting

## Trade-offs

✅ Near-Opus reasoning for specific decisions  
✅ Sonnet cost for 80% of work  
✅ Explicit, observable checkpoints (no guessing "when stuck")  
❌ Requires defining decision points upfront  
❌ Extra latency per escalation (~2-5s for Opus thinking)  

## Testing

See `SKILL.md` for:
- Complete eval script (runnable)
- Sample tasks with ground truth
- Monitoring metrics and alerts
- Failure modes and fixes

## Learn More

- Read `SKILL.md` for full implementation details
- Check `eval_tasks` in SKILL.md for realistic examples
- See "Common Failure Modes" section for troubleshooting

---

**Author:** Built with the agent-skills ecosystem  
**Status:** Code Review stable; Research in progress  
**License:** MIT
