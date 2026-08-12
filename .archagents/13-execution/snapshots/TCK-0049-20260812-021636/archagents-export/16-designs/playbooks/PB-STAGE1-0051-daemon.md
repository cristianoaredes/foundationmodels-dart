# Playbook — TCK-0051 Stage 1 daemon live

1. Probe binary (`--help` / health); log exit.  
2. If fail → try monorepo rebuild; else reaffirm env_limit.  
3. If ok → dual-run via `DaemonSocketTransport`; env-gate tests.  
4. Keep fake peer green.  
5. Close ticket done or blocked+dated.  
