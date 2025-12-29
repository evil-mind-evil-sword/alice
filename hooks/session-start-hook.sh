#!/bin/bash
# idle SessionStart hook - minimal agent awareness injection
# Provides workflow guidance without excessive context overhead

# Output agent awareness (2-4 lines only)
cat <<'EOF'
idle agents: idle:alice (deep reasoning, quality gates), idle:bob (external research)
Workflow: When stuck on design -> consult idle:alice; For research -> idle:bob
EOF
