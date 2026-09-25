# GLOBAL LLAMA.CPP BENCHMARK + CONFIGURATION DISCOVERY PROMPT

You are an AI agent operating directly on a user's computer.

Your task is to comprehensively benchmark the currently configured local Llama.cpp model and determine the best practical runtime configurations for the actual machine.

This is a hardware-aware, model-aware benchmarking and configuration-discovery task.

Do not assume that a configuration that worked on another computer will work here.

Do not optimize only for one benchmark number.

The goal is to discover the practical performance envelope and produce several stable configurations for different workloads.

---

# 1. CORE RULES

## Never guess

First inspect:

- operating system;
- OS version/build;
- CPU;
- physical CPU cores;
- logical threads;
- RAM;
- available RAM;
- GPU;
- VRAM;
- available VRAM;
- driver;
- Llama.cpp version;
- backend;
- model;
- model architecture;
- model size;
- quantization;
- native context;
- existing configuration;
- current server state.

If something important cannot be determined reliably, investigate it.

If it still cannot be determined, ask the user.

Never invent benchmark results.

---

# 2. PROTECT THE MODEL

The model file is immutable.

NEVER:

- modify it;
- requantize it;
- convert it;
- overwrite it;
- delete it;
- alter it.

All optimization must happen through runtime configuration.

Before benchmarking, verify the model file's identity and preserve it.

---

# 3. PRESERVE THE EXISTING CONFIGURATION

Before making changes:

1. locate the current model configuration;
2. create a backup;
3. record the current working configuration;
4. record the current Llama.cpp command;
5. record the current server state.

Do not destroy a working configuration.

If a benchmark fails, the original configuration must remain recoverable.

---

# 4. VERIFY THE BENCHMARK ENVIRONMENT

Determine whether other applications are consuming resources.

Measure where possible:

- CPU utilization;
- RAM usage;
- GPU utilization;
- GPU memory usage;
- system/shared GPU memory;
- available VRAM;
- available RAM.

Identify major competing workloads such as:

- browsers;
- VS Code;
- IDEs;
- video applications;
- Blender;
- Docker;
- virtual machines;
- other AI processes;
- background GPU applications.

Do not falsely interpret a workstation workload as pure AI performance.

Record the environment before benchmark execution.

---

# 5. VERIFY LLAMA.CPP OPTIONS

Inspect the actual installed Llama.cpp version.

Do not assume command-line flags.

Determine which options are supported for:

- context;
- GPU layers;
- batch;
- micro-batch;
- CPU threads;
- parallel slots;
- Flash Attention;
- KV cache types;
- device selection;
- generation;
- metrics;
- logging.

Only benchmark parameters that are actually supported.

---

# 6. BENCHMARKING PRINCIPLE

Do NOT use the inefficient method:

> change one setting → benchmark → change another → benchmark → repeat randomly.

Instead, create a structured benchmark matrix before running the tests.

The benchmark plan should cover the relevant configuration dimensions systematically.

Use a coarse-to-fine search:

### Phase A — Establish baseline

Run the current known configuration.

Record:

- prompt processing speed;
- generation speed;
- total time;
- tokens processed;
- context;
- peak VRAM;
- peak RAM;
- CPU utilization;
- GPU utilization;
- whether CPU offload occurred;
- whether shared GPU memory was used;
- errors;
- stability.

---

# 7. CONTEXT-SIZE SWEEP

Determine practical context limits.

Start from a safe small context and progressively test larger contexts.

Use sensible sizes such as:

- 4K;
- 8K;
- 12K;
- 16K;
- 24K;
- 32K;
- 36K;
- 40K;
- 48K;
- 56K;
- 64K;
- and larger only if the model and hardware make it reasonable.

Do NOT blindly test every theoretical context size.

Stop escalating when:

- OOM occurs;
- severe paging occurs;
- shared GPU memory becomes dominant;
- performance collapses;
- the server becomes unstable.

Record the actual failure boundary.

Do not claim that a context size is supported merely because the model metadata says it is.

Distinguish:

- native model context;
- technically launchable context;
- practically usable context;
- production-recommended context.

---

# 8. GPU OFFLOAD SWEEP

Determine the performance relationship between GPU offload and CPU/hybrid execution.

Test a sensible range based on the model's layer count.

For example:

- partial offload;
- approximately 25%;
- approximately 50%;
- approximately 75%;
- near-full;
- full GPU offload.

Translate these into actual supported Llama.cpp values.

Do not blindly use the example percentages.

Measure:

- prompt speed;
- generation speed;
- VRAM;
- RAM;
- GPU utilization;
- stability.

Identify the point where additional offloading stops being beneficial or causes memory pressure.

---

# 9. KV CACHE SWEEP

Where supported, test appropriate KV-cache modes.

At minimum consider:

- f16;
- q8_0;
- q4_0.

Only test modes supported by the actual Llama.cpp/model/backend combination.

Measure the effect on:

- context capacity;
- VRAM;
- prompt speed;
- generation speed;
- stability.

Do not select a lower-precision cache merely because it saves memory.

Measure the tradeoff.

---

# 10. FLASH ATTENTION

Test:

- Flash Attention enabled;
- Flash Attention disabled;

when the backend supports both.

Record the actual difference.

Do not assume Flash Attention is always faster on every backend/model.

---

# 11. BATCH AND MICRO-BATCH SWEEP

Test a reasonable range based on the machine.

Potential values include:

- batch 256;
- 512;
- 1024;
- 2048;
- higher only if justified.

For micro-batch:

- 64;
- 128;
- 256;
- 512;
- higher only if justified.

Do not blindly test every combination if earlier results clearly establish an invalid or harmful region.

Use measured results to narrow the search.

---

# 12. CPU THREAD SWEEP

Determine useful CPU thread counts.

Consider:

- physical cores;
- logical threads;
- competing applications.

Test sensible values such as:

- 2;
- 4;
- physical-core count;
- logical-thread count;

where appropriate.

Do not assume that maximum thread count gives maximum performance.

Especially test the difference between:

- dedicated AI workload;
- normal development workload.

---

# 13. PARALLELISM

Evaluate parallel slots carefully.

The default target is a single agent/session unless the user's workload requires multiple concurrent requests.

Do not increase parallelism merely because the option exists.

Parallelism can multiply memory pressure.

If multiple slots are tested, measure:

- throughput;
- latency;
- VRAM;
- RAM;
- stability.

---

# 14. REALISTIC AGENT BENCHMARKING

Do not benchmark only a tiny artificial prompt.

The user intends to use the model as an AI coding agent.

Therefore test representative workloads where possible.

Include contexts representing:

### Small agent request

Several thousand tokens.

### Medium agent request

Approximately 8K–16K tokens.

### Large agent request

Approximately 24K–36K tokens.

### Growing agent session

Simulate a session where context grows through:

- source files;
- tool results;
- terminal output;
- debugging;
- generated code;
- repeated user/agent turns.

Do NOT assume that the user's context will always remain at one fixed number.

Measure how performance changes as context grows.

---

# 15. IMPORTANT: AGENT CONTEXT IS NOT FIXED

The user may begin with a 10K context and later reach:

20K → 30K → 40K → 50K+

depending on:

- repository size;
- files read;
- tool results;
- conversation history;
- debugging;
- test output;
- generated code.

Therefore determine the practical context ceiling.

A configuration that is extremely fast at 8K but collapses at 30K should not be considered the best general-purpose agent configuration.

---

# 16. RESOURCE-HEADROOM TESTING

Do not optimize only for maximum benchmark numbers.

The operating system requires resources.

Therefore determine separate configurations for different resource budgets.

At minimum create:

## PROFILE A — MAXIMUM AI / DEDICATED

The machine is primarily dedicated to the AI agent.

Requirements:

- maximize useful model performance;
- maximize practical context;
- use aggressive GPU offload where stable;
- use high batch settings where beneficial;
- still leave enough resources for the operating system;
- avoid configurations that cause system instability or severe shared-memory paging.

This profile should represent the best configuration for dedicated AI-agent work.

---

## PROFILE B — CO-WORK / DEVELOPMENT

The user will run:

- AI agent;
- VS Code;
- terminal;
- one or two Chrome profiles;
- Git;
- normal development tools.

Requirements:

- leave CPU headroom;
- leave RAM headroom;
- leave VRAM headroom;
- avoid GPU shared-memory pressure;
- avoid excessive context memory;
- maintain practical agent responsiveness.

This profile should prioritize the overall workstation experience rather than raw AI benchmark numbers.

---

## PROFILE C — MINIMUM / SAFE

Create a conservative profile.

Purpose:

- lowest practical resource consumption;
- maximum stability;
- useful when the machine is heavily occupied;
- avoid OOM;
- avoid swap/paging;
- avoid shared GPU memory thrashing.

It does not need to be fast.

It needs to remain usable and stable.

---

# 17. DO NOT OPTIMIZE ONLY FOR TOKENS/SECOND

Evaluate multiple dimensions.

For every candidate configuration record:

- prompt tokens/second;
- generation tokens/second;
- time to first token if available;
- total generation time;
- context size;
- peak VRAM;
- free VRAM;
- peak RAM;
- CPU usage;
- GPU usage;
- shared GPU memory;
- stability;
- errors;
- OOM;
- paging/thrashing;
- quality-impacting settings;
- whether the configuration is practical for the intended workload.

A configuration that achieves slightly higher tokens/sec but causes system paging should not be selected as a production configuration.

---

# 18. DETERMINE THE PERFORMANCE CEILING

Find:

1. maximum stable GPU offload;
2. maximum practical context;
3. best KV-cache mode;
4. best Flash Attention state;
5. best batch;
6. best micro-batch;
7. useful CPU thread count;
8. safe parallelism;
9. resource headroom.

Identify where performance starts degrading.

The objective is to find the practical "sweet spot", not merely the largest possible number.

---

# 19. TEST FAILURE BOUNDARIES SAFELY

Testing the ceiling is required, but do it safely.

If a configuration causes:

- OOM;
- GPU driver instability;
- severe shared-memory paging;
- system freeze;
- runaway RAM;
- runaway VRAM;
- repeated server crashes;

stop escalating that dimension.

Record:

- configuration;
- failure type;
- approximate resource usage;
- error;
- whether the system recovered.

Do not repeatedly reproduce a dangerous failure merely to obtain another measurement.

---

# 20. BENCHMARK MATRIX

Before execution, construct a benchmark matrix.

Use a staged search:

### Stage 1

Find viable ranges.

### Stage 2

Find the best region.

### Stage 3

Fine-tune around the best region.

### Stage 4

Validate the final candidates under realistic workloads.

This prevents thousands of unnecessary combinations.

Do not simply perform a random parameter sweep.

---

# 21. REPEATABILITY

For important candidate configurations:

- repeat the benchmark;
- compare results;
- detect unusually noisy measurements.

Do not select a configuration based on one anomalous result.

Record whether results are:

- consistent;
- variable;
- affected by competing workloads.

---

# 22. CONFIGURATION OUTPUT

Create a dedicated configuration directory.

Example:

`configurations/`

Inside it create clearly named configuration files, such as:

- `maximum-ai`
- `cowork-development`
- `minimum-safe`

Use the appropriate extension/format for the setup architecture.

Each configuration must contain all relevant runtime settings.

Do not require the user to remember undocumented command-line overrides.

---

# 23. BENCHMARK RESULTS

Create a dedicated directory:

`benchmark-results/`

Store:

- raw benchmark output;
- structured results;
- environment information;
- tested configurations;
- failures;
- selected configurations;
- final recommendations;
- timestamps;
- Llama.cpp version;
- model identity.

Do not overwrite previous benchmark runs.

Use a timestamp/versioned structure.

For example:

`benchmark-results/<date-or-run-id>/`

---

# 24. BENCHMARK REPORT

Create a human-readable report.

It should contain:

## Environment

- OS;
- CPU;
- RAM;
- GPU;
- VRAM;
- driver;
- Llama.cpp version;
- backend.

## Model

- model name;
- architecture;
- parameter count;
- quantization;
- model size;
- native context.

## Baseline

Current configuration and performance.

## Tested ranges

Show what was tested for:

- context;
- GPU offload;
- KV cache;
- Flash Attention;
- batch;
- micro-batch;
- threads;
- parallelism.

## Performance table

Include:

- configuration;
- context;
- prompt tok/s;
- generation tok/s;
- latency;
- VRAM;
- RAM;
- stability.

## Failure boundaries

Document:

- OOM;
- thrashing;
- crashes;
- unsupported configurations.

## Final profiles

Document the selected:

1. Maximum AI;
2. Co-work/Development;
3. Minimum/Safe.

---

# 25. CONFIGURATION SELECTION RULE

Do not choose configurations based on one metric.

For each final profile, balance:

- performance;
- context capacity;
- memory consumption;
- stability;
- workload suitability.

Do not silently prioritize speed over context.

Do not silently prioritize context over usability.

The selection criteria must be visible in the report.

---

# 26. QUALITY PRESERVATION

Do not modify the model to improve benchmark results.

Do not:

- requantize;
- convert;
- prune;
- merge;
- alter weights.

Runtime optimizations are allowed only when supported by the actual Llama.cpp build.

---

# 27. PRODUCTION VALIDATION

After selecting the three configurations, actually validate each final configuration.

For each:

1. start the server;
2. verify health;
3. send a representative request;
4. verify generation;
5. inspect resource usage;
6. verify stability;
7. stop the server;
8. verify the process exits;
9. verify the port closes;
10. verify resources are released.

Do not declare a configuration production-ready merely because it benchmarked well.

---

# 28. RESTORE / LEAVE SYSTEM IN A GOOD STATE

At the end:

- stop temporary benchmark servers;
- remove orphan processes created by the benchmark;
- close temporary resources;
- restore the selected production configuration;
- start the selected default profile only if the user requested automatic startup;
- otherwise leave the server stopped.

Never terminate unrelated applications.

Never broadly kill processes.

---

# 29. IF THE MODEL CANNOT BE OPTIMALLY CONFIGURED

If the hardware cannot practically support the model:

do not hide the problem.

Clearly report:

- what the hardware can handle;
- what the model requires;
- where the limitation occurs;
- what compromises are available.

Possible compromises may include:

- smaller context;
- reduced GPU offload;
- lower KV precision;
- lower batch;
- lower parallelism.

Do not recommend downloading a different model unless the user specifically asks for model-selection advice.

---

# 30. FLAG BAD PRACTICES

If you discover that an existing setup contains a questionable practice, explicitly flag it.

Examples:

- secrets embedded in scripts;
- API keys exposed in logs;
- broad process killing;
- unsupported Llama.cpp flags;
- public network binding;
- excessive context causing paging;
- running entirely from shared GPU memory;
- hardcoded model paths that prevent reuse;
- undocumented command-line overrides;
- modifying model files;
- benchmarking while another AI model is consuming the GPU.

Do not silently preserve a dangerous practice.

---

# 31. FINAL DELIVERABLES

At completion, the system should contain:

## Reusable configurations

`configurations/`

with at least:

- Maximum AI;
- Co-work/Development;
- Minimum/Safe.

## Benchmark results

`benchmark-results/`

with complete raw and summarized data.

## Benchmark report

A human-readable report containing the complete findings.

## Current production configuration

The selected default configuration should be clearly identified.

---

# 32. FINAL RESPONSE TO THE USER

When finished, report only factual results.

Include:

- detected hardware;
- model;
- Llama.cpp version/backend;
- practical maximum context;
- best dedicated-AI configuration;
- best co-work configuration;
- minimum-safe configuration;
- major performance measurements;
- important failure boundaries;
- any unresolved issues;
- locations of the generated configurations and benchmark results.

Do not claim a configuration is "best" merely because it has the highest tokens/second.

Use "best for [specific workload]" and support that conclusion with measured data.

If the benchmark could not reliably establish a conclusion, say so.

Never invent missing benchmark results.

Never hide failures.

Never modify the model.

Never guess.
