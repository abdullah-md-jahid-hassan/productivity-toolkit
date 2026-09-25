# GLOBAL LLAMA.CPP SETUP-PROMPT GENERATOR

You are an AI agent operating directly on a user's computer.

Your task is to analyze the current computer, understand its operating system, hardware, software environment, available resources, existing Llama.cpp installations, and the user's established preferences, and then create a reusable document named:

`llama_model_setup.md`

This document will later be reused whenever the user downloads a new local LLM model.

The purpose of this prompt is NOT to install a model immediately.

Your first responsibility is to create a reliable, machine-specific, reusable setup instruction that another AI agent can follow later to install and configure any compatible local LLM model on this machine.

---

# 1. IMPORTANT OPERATING PRINCIPLES

Follow these principles throughout the entire task.

## 1.1 Never guess missing information

If required information is unavailable, ambiguous, inaccessible, or contradicts existing information:

- investigate it first;
- if it still cannot be determined reliably, ask the user;
- never silently guess;
- never invent hardware specifications;
- never invent supported Llama.cpp options;
- never assume a GPU backend exists;
- never assume a shell, package manager, service manager, filesystem layout, or operating system behavior.

If you have lost important context from previous instructions, ask the user instead of reconstructing it from assumptions.

---

## 1.2 This prompt must be OS-independent

The procedure must work across operating systems where Llama.cpp can reasonably run.

Do not assume:

- Windows;
- Linux;
- macOS;
- PowerShell;
- Bash;
- systemd;
- CUDA;
- NVIDIA;
- AMD;
- Apple Silicon;
- a specific package manager;
- a specific filesystem;
- a specific installation directory.

First detect the environment.

Then generate instructions appropriate for that environment.

The resulting `llama_model_setup.md` may contain OS-specific commands where necessary, but the GLOBAL prompt itself must remain operating-system-independent.

---

# 2. COMPLETE SYSTEM AUDIT

Before creating the reusable setup document, perform a comprehensive system audit.

Do not stop after discovering the basic OS and CPU.

Determine, as accurately as possible:

## Operating system

Identify:

- operating system;
- distribution/edition;
- version;
- build/release;
- architecture;
- kernel version where applicable;
- native vs virtualized environment;
- subsystem/container/VM environment if applicable.

## CPU

Determine:

- CPU model;
- architecture;
- physical cores;
- logical threads;
- available instruction sets where relevant;
- current CPU utilization;
- whether CPU resources are constrained or shared.

## GPU

Identify every relevant GPU.

For each GPU determine:

- vendor;
- model;
- dedicated/shared/integrated;
- VRAM;
- available VRAM;
- driver version;
- compute capability/backend if applicable;
- supported acceleration backend;
- current utilization;
- current memory usage.

Detect applicable backends such as:

- CUDA;
- ROCm/HIP;
- Vulkan;
- Metal;
- SYCL;
- CPU;
- other officially supported Llama.cpp backends.

Do not assume that the presence of a GPU means Llama.cpp can use it.

Verify the actual usable backend.

## RAM

Determine:

- total RAM;
- available RAM;
- currently used RAM;
- swap/pagefile configuration;
- whether memory is unusually constrained.

## Storage

Determine:

- available storage;
- filesystem;
- location suitable for model storage;
- storage type if detectable;
- whether the model directory has enough capacity;
- whether temporary files may require additional capacity.

## Existing Llama.cpp

Search for existing installations.

Determine:

- whether Llama.cpp already exists;
- executable/binary location;
- version;
- build information;
- available backend;
- supported command-line arguments;
- whether it is a source build or packaged build;
- whether it should be reused or replaced.

Do not replace a working installation merely because another installation method exists.

Prefer the simplest reliable existing installation when it is appropriate.

## Existing local models

Look for existing model directories and determine:

- model formats;
- model sizes;
- naming conventions;
- existing configuration patterns;
- existing start/stop mechanisms;
- existing ports;
- whether another local model server is already running.

Do not modify or delete existing models.

---

# 3. VERIFY LLAMA.CPP CAPABILITIES

Do not rely only on remembered Llama.cpp command-line options.

Inspect the actual installed version.

Use its available help/version/build information to determine:

- model argument;
- host;
- port;
- context size;
- GPU layer/offload controls;
- batch size;
- micro-batch size;
- CPU thread controls;
- parallel slots;
- Flash Attention;
- KV-cache types;
- device selection;
- generation controls;
- API authentication;
- logging;
- metrics/health endpoints;
- any other relevant server options.

Only document options that are actually supported by the discovered Llama.cpp version.

If Llama.cpp needs to be installed or built, determine the best native method for the detected OS and hardware.

Do not introduce Docker, reverse proxies, LiteLLM, or unrelated infrastructure unless the user explicitly requests it.

---

# 4. DEFINE THE STANDARD ARCHITECTURE

Create a clean architecture that separates:

1. global Llama.cpp installation;
2. individual model files;
3. model-specific configuration;
4. model-specific start/stop controls;
5. logs;
6. runtime metadata;
7. benchmark results;
8. production configurations;
9. documentation.

The exact filesystem paths must be selected based on the operating system.

Do not blindly copy paths from another machine.

The architecture should conceptually look like:

Llama.cpp installation
|
+-- models/
| |
| +-- Model-A/
| | +-- model file
| | +-- config
| | +-- start
| | +-- stop
| | +-- logs/
| | +-- runtime/
| |
| +-- Model-B/
|
+-- configurations/
|
+-- benchmark-results/
|
+-- documentation/

Adapt the actual layout to the detected OS.

---

# 5. MODEL FILE PROTECTION

The model itself is an immutable asset.

The future setup procedure must NEVER:

- modify the model file;
- requantize the model;
- convert the model;
- rename the model unnecessarily;
- overwrite the model;
- delete the model;
- alter model metadata embedded in the file.

If optimization is necessary, optimize the Llama.cpp runtime configuration around the model.

If a model appears incompatible with the installed Llama.cpp version, report the issue instead of modifying the model.

---

# 6. CONFIGURATION-DRIVEN STARTUP

The future setup procedure must be configuration-driven.

Do not hardcode every runtime parameter directly into the startup script.

The model configuration should contain the relevant settings, such as:

- model path;
- model alias;
- host;
- port;
- network access;
- API key file;
- context size;
- GPU offload;
- batch size;
- micro-batch size;
- CPU threads;
- parallel slots;
- Flash Attention;
- KV-cache configuration;
- device;
- generation settings;
- logging settings.

The exact names must match the actual configuration parser and Llama.cpp version.

The startup script should read the configuration and construct the correct Llama.cpp command.

---

# 7. NETWORKING

Default behavior should be secure.

Local-only operation should be preferred unless LAN access is explicitly required.

Support a configuration switch equivalent to:

- localhost/local-only;
- trusted LAN access.

If LAN access is enabled:

- clearly document the security implications;
- use API authentication where supported;
- never expose the API key in documentation;
- never print secrets unnecessarily;
- never commit secrets to source control;
- keep the secret in a separate protected file;
- use the safest native permissions available on the OS.

Do not expose the service to the public internet.

Do not add a reverse proxy merely because it is technically possible.

---

# 8. START SCRIPT REQUIREMENTS

Create a reusable start mechanism appropriate for the detected operating system.

It must:

1. validate the configuration;
2. validate the model exists;
3. validate the Llama.cpp executable;
4. validate the selected device/backend where possible;
5. check whether the model server is already running;
6. detect an existing instance belonging to this model;
7. avoid accidentally starting duplicates;
8. start the server cleanly;
9. detach it appropriately for the operating system;
10. capture useful logs;
11. record runtime metadata;
12. wait for the server health endpoint;
13. verify that the server actually became ready;
14. report useful errors if startup fails.

Do not create a script that blindly launches another process every time it is executed.

---

# 9. STOP SCRIPT REQUIREMENTS

Create a corresponding stop mechanism.

It must be:

- safe;
- idempotent;
- model-specific;
- conservative.

It must NEVER:

- kill every Llama.cpp process;
- kill every process using a port;
- broadly terminate unrelated processes;
- force-kill unrelated development applications.

Before terminating a process, verify that it belongs to the intended model/server using reliable process identity information.

After stopping:

- verify the process is gone;
- verify the server port is released;
- verify the model server is no longer responding;
- report GPU/RAM resource release where measurable.

If graceful shutdown is available, prefer it before force termination.

---

# 10. LOGGING AND RUNTIME INFORMATION

Create a clean logging structure.

Separate:

- startup information;
- server logs;
- errors;
- runtime metadata;
- benchmark logs.

Do not allow logs to grow indefinitely without consideration.

Runtime metadata should make it possible to determine:

- which model is running;
- which configuration is active;
- which process owns the server;
- which port is being used;
- when it started;
- which device/backend is being used.

---

# 11. PORT MANAGEMENT

Do not blindly assume a port.

Determine a sensible default based on existing services.

The generated reusable setup document should define a consistent model-server port strategy.

For example, if multiple models may coexist:

- Model A → one port;
- Model B → another port.

Before starting a model:

- verify the port;
- identify what is using it;
- never blindly terminate another service.

---

# 12. FUTURE MODEL SETUP PROCEDURE

The generated `llama_model_setup.md` must contain a complete procedure that another AI agent can follow whenever the user gives it a new model.

That future procedure must perform, in order:

1. inspect the model file;
2. identify model format;
3. identify architecture;
4. determine parameter count if possible;
5. determine quantization;
6. determine native context;
7. determine model capabilities;
8. determine compatibility with the installed Llama.cpp;
9. verify available hardware;
10. estimate whether the model fits in available VRAM/RAM;
11. create the model directory;
12. preserve the model untouched;
13. create the model configuration;
14. create the start mechanism;
15. create the stop mechanism;
16. create logging/runtime directories;
17. create documentation;
18. perform a basic startup test;
19. verify the API;
20. verify shutdown;
21. leave the model ready for later benchmarking.

Do not assume that a model fits merely because its file size is smaller than VRAM.

Consider:

- model weights;
- KV cache;
- context length;
- runtime buffers;
- CUDA/driver/backend overhead;
- OS/display overhead;
- other GPU applications;
- CPU RAM requirements;
- temporary/shared memory;
- batch size;
- GPU offload.

---

# 13. RESOURCE PROFILES

The generated setup system should support multiple runtime profiles rather than one permanent configuration.

At minimum, design the architecture so it can support:

## Maximum / Dedicated AI

For when the machine is primarily dedicated to the AI agent.

It should maximize useful model performance while preserving enough resources for the operating system to remain stable.

## Co-work / Development

For when the AI agent runs alongside:

- VS Code;
- terminal;
- browser;
- one or two browser profiles;
- Git;
- normal development tools.

This profile must deliberately leave CPU/RAM/VRAM headroom.

## Minimum / Safe

A conservative configuration intended to make the model usable on a resource-constrained machine.

It should prioritize:

- stability;
- avoiding OOM;
- avoiding swap/paging;
- avoiding GPU shared-memory thrashing;
- reliable operation.

The exact values must be determined from the actual machine and model rather than copied from another machine.

---

# 14. CONTEXT MANAGEMENT

Do not automatically configure the model to its theoretical maximum context.

Theoretical/native context and practical context are different.

The future setup and benchmark process must consider:

- model-native context;
- available VRAM;
- KV-cache memory;
- batch size;
- GPU offload;
- generation performance;
- prompt processing performance;
- operating-system headroom.

The configuration should prefer a practical stable context over a theoretical maximum that causes paging, OOM, or severe performance degradation.

---

# 15. CLAUDE CODE / AGENT COMPATIBILITY

The local server should expose a standard API compatible with the user's AI-agent workflow where possible.

The generated setup document must explain:

- endpoint;
- model alias;
- authentication;
- required environment variables if applicable;
- how to start;
- how to stop;
- how to verify availability.

Do not hardcode Claude Code-specific assumptions that would prevent another OpenAI-compatible client from using the server.

---

# 16. FAILURE HANDLING

The future setup procedure must stop and report clearly when:

- model format is unsupported;
- Llama.cpp version is incompatible;
- required backend is unavailable;
- VRAM is insufficient;
- RAM is insufficient;
- storage is insufficient;
- required runtime feature is unavailable;
- port conflicts cannot safely be resolved;
- configuration options are unsupported.

Do not "solve" such problems by silently lowering quality or modifying the model.

Explain the actual limitation and ask for a decision when necessary.

---

# 17. DOCUMENTATION TO CREATE

Create `llama_model_setup.md` containing:

1. machine-specific environment summary;
2. Llama.cpp installation information;
3. directory architecture;
4. model setup procedure;
5. configuration format;
6. start procedure;
7. stop procedure;
8. health/API verification;
9. networking/security;
10. logging;
11. troubleshooting;
12. resource-profile structure;
13. rules for protecting model files;
14. rules for handling secrets;
15. rules for future model installations.

The document must be written so that another AI agent can execute it without needing this original GLOBAL prompt.

---

# 18. FINAL VALIDATION

Before declaring the task complete:

- verify the detected hardware;
- verify the detected OS;
- verify Llama.cpp;
- verify the chosen installation architecture;
- verify the generated commands against the actual environment;
- verify that no unsupported flags were documented;
- verify that model files are protected;
- verify that secrets are not exposed;
- verify that start/stop design is safe;
- verify that the configuration can support multiple resource profiles.

Do not install a model during this task unless necessary to validate the Llama.cpp installation.

The primary deliverable is:

`llama_model_setup.md`

At the end, report:

- what was detected;
- where the reusable document was created;
- what assumptions were avoided;
- any unresolved issue requiring the user's decision.

If something important cannot be established reliably, ask the user instead of guessing.
