- # Claude Code + Codex MCP Collaboration

## Core Principles

1. **Separation of Concerns**: CC = brain (planning, search, decisions), Codex = hands (code generation, refactoring)
2. **Codex-First Strategy**: Default to Codex for code tasks, CC only for trivial changes (<20 lines) andnon-codework
3. **Zero-ConfirmationFlow**:Pre-definedboundaries, auto-executewithinlimits

---

## CoreRules

### Linus'sThreeQuestions (Pre-Decision)

1.Isthisarealproblemorimagined? → Rejectover-engineering
2.Isthereasimplerway? → Alwaysseeksimplestsolution
3.Whatwillthisbreak? → Backwardcompatibilityisironlaw

### CCResponsibilities

- ✅ Plan, search (WebSearch/Glob/Grep), decide, coordinateCodex
- ✅ Trivialchangesonly:typofixes, commentupdates, simpleconfigtweaks (<20lines)
- ❌ Nofinalcodeinplanningphase
- ❌ Delegateallcodegeneration/refactoringtoCodex (evensimpletasks)

### QualityStandards

-Simplifydatastructuresoverpatchinglogic
-Nouselessconceptsintaskbreakdown
- > 3 indentation levels → redesign
- Complex flows → reduce requirements first

### Safety

- Check API/data breakage before changes
- Explain new flow compatibility
- High-risk changes only with evidence
- Mark speculation as "assumption"

### Codex Participation Priority

**IMPORTANT**: Maximize Codex involvement for all code-related tasks

- ✅ Single function modification → Codex
- ✅ Adding a new method → Codex
- ✅ Refactoring logic → Codex
- ✅ Bug fixes → Codex
- ❌ Only skip Codex for: typo fixes, comment-only changes, trivial config tweaks (<20 lines)

---

## MCPInvocation

### SessionManagement

// Firstcall
mcp**codex**codex({
model: "gpt-5-codex",
sandbox: "danger-full-access",
approval-policy: "on-failure",
prompt: "<structuredprompt>"
})
// Save conversationId

// Subsequent calls
mcp**codex**codex_reply({
conversationId: "<saved ID>",
prompt: "<next step>"
})

### Auto-Confirmation

**✅ Auto-continue**: Modify existing files (in scope), add tests, run linter, read-only ops
**⛔ Pause**: Modify package.json deps, change public API, delete files, modify configs

---

## Routing Matrix (Codex-First)

| Task                | Executor  | Trigger                                              | Reason                                 |
| ------------------- | --------- | ---------------------------------------------------- | -------------------------------------- |
| Code changes        | **Codex** | Any code modification (functions, logic, components) | Strong generation, always prefer Codex |
| Single-file edit    | **Codex** | Even <50 lines if involves logic/code                | Better code understanding              |
| Multi-file refactor | **Codex** | >1 file with code changes                            | Global understanding                   |
| New feature         | **Codex** | Any new functionality                                | Strong generation                      |
| Bug fix             | **Codex** | Need trace or logic fix                              | Strong search + fix                    |
| Trivial changes     | **CC**    | Typos, comments, simple configs (<20 lines)          | ToosimpleforCodex                   |
| Non-codework       | **CC**    | Pure.md/.json/.yaml (nologic)                      | Nocodegenerationneeded              |
| Architecture        | **CC**    | Puredesigndecision                                 | Planningstrength                      |

**DecisionFlow**:UserRequest → Linus3Q → Assess → **DefaulttoCodexforcode** → OnlyCCfortrivial/non-code

---

## Workflow (4Phases)

### 1.InfoCollection (CC)

-WebSearch:latestdocs/practices
-Glob/Grep:analyzecodestructure
-Output:contextreport (techstack, files, patterns, risks)

### 2.TaskPlanning (CCPlanMode)

## TechSpec

Goal: [onesentence]
Tech: [lib/framework]
Risks: [breakingchanges]
Compatibility: [howtoensure]

## Tasks

- [ ] Task1: [desc] | Executor:CC/Codex | Files: [paths] | Constraints: [limits] | Acceptance: [criteria]
- [ ] Task2:...

### 3.Execution (Codex-First)

- **Codex (Default)**:Allcode-relatedtasks → Callwithstructuredprompt, saveconversationId, monitor
- **CC (ExceptionOnly)**:Trivialnon-codework → Edit/Writetoolsfortypos, puredocs, simpleconfigs (<20lines)

### 4.Validation

- [ ] Functionality ✓ | Tests ✓ | Types ✓ | Performance ✓ | NoAPIbreak ✓ | Style ✓
-Codexrunschecks → CCdecides → Ifissues, backtoPhase3

---

## CodexPromptTemplate (MUSTUSE)

## Context

-TechStack: [lang/framework/version]
-Files: [path]: [purpose]
-Reference: [filepathforpattern/style]

## Task

[Clear, single, verifiabletask]
Steps:1. [step] 2. [step] 3. [step]

## Constraints

-API:Don'tchange [signatures]
-Performance: [metrics]
-Style:Follow [reference]
-Scope:Only [files]
-Deps:Nonewdependencies

## Acceptance

- [ ] Testspass (`npmtest`)
- [ ] Typespass (`tsc--noEmit`)
- [ ] Linterpass (`npmrunlint`)
- [ ] [Project-specific]

---

## Anti-Patterns (AVOID)

| Pattern                           | Problem                        | Fix                                                      |
| --------------------------------- | ------------------------------ | -------------------------------------------------------- |
| CCdoingcodework                | WasteCodex'sstrength         | UseCodexforallcodechanges (evensimple)             |
| Noboundaries                     | Highfailure, breakscode      | Structuredpromptrequired                               |
| Confirmationloops                | Lowefficiency                 | Pre-defineautoboundaries                               |
| IgnoringCodexfor "simple" edits | Misscodequalityimprovements | DefaulttoCodexunlesstrivial (<20linestypo/comment) |
| Vaguetasks                       | Codexcan'tunderstand         | Specific, measurable, verifiable                         |
| Ignorecompatibility              | Breakusercode                | ExplaininConstraints                                   |

---

## SuccessMetrics

**Efficiency**:90% auto (nomanualconfirm) | <2minavgcycle | >80% first-time success
**Quality**: Zero API break | Test coverage maintained | No performance regression
**Experience**: Clear breakdown | Transparent progress | Recoverable errors

---

## Optional Config

# Retry

max-iterations: 3
retry-strategy: exponential-backoff

# Presets

context-presets:
react: { tech: "React 18 + TS", test: "npm test", lint: "npm run lint" }
python: { tech: "Python 3.11 + pytest", test: "pytest", lint: "ruff" }

# Checklist

review: [tests, types, linter, perf, api-compat, style]

# Fallback

fallback:
codex-fail-3x: { action: switch-to-cc, notify: "3 fails, manual mode" }
api-break: { action: abort, notify: "API break detected" }