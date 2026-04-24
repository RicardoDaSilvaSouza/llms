# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository contains a local LLM infrastructure setup combining:
- **LiteLLM Proxy**: OpenAI-compatible proxy that routes requests to local LLMs on RTX 4080 rig
- **local-memory-mcp**: PostgreSQL + Ollama-based semantic memory MCP server for persistent AI memory
- **Shared Infrastructure**: PostgreSQL (pgvector) and Ollama services supporting both components

The system is orchestrated via Docker Compose for local development and deployment.

## Architecture

### Service Architecture

```
┌─────────────────────────────────────────────┐
│ Client (Claude Code via LiteLLM Proxy)      │
└──────────────────┬──────────────────────────┘
                   │
        ┌──────────▼───────────┐
        │   LiteLLM Proxy      │ (port 4000)
        │   (routes to RTX80)  │
        └──────────┬───────────┘
                   │
        ┌──────────▼───────────────────────────────────┐
        │        Shared Infrastructure                 │
        │ ┌────────────────────────────────────────┐  │
        │ │  PostgreSQL + pgvector (port 5432)     │  │
        │ │  - LiteLLM persistence                 │  │
        │ │  - local-memory-mcp semantic storage   │  │
        │ └────────────────────────────────────────┘  │
        │ ┌────────────────────────────────────────┐  │
        │ │  Ollama (port 11434)                   │  │
        │ │  - Embedding models (nomic-embed-text) │  │
        │ │  - Other local LLMs                    │  │
        │ └────────────────────────────────────────┘  │
        └──────────────────────────────────────────────┘
                   │
        ┌──────────▼──────────────┐
        │  local-memory-mcp       │
        │  (stdio MCP transport)  │
        └─────────────────────────┘
```

### Key Design Decisions

1. **Shared Database**: PostgreSQL serves both LiteLLM and local-memory-mcp, avoiding duplicate data stores
2. **Docker Socket Access**: LiteLLM container mounts docker socket to run local-memory-mcp via `docker exec`
3. **MCP stdio Transport**: local-memory-mcp runs as stdio-based MCP (invoked on-demand by Claude Code), not as a long-running server
4. **Model Routing**: config.yaml defines available models; LiteLLM routes to RTX 4080 rig or Ollama based on configuration

## Common Commands

### Docker Compose Operations

```bash
# Start all services (db, ollama, litellm, local-memory-mcp)
docker-compose up -d

# Stop all services
docker-compose down

# View logs for all services
docker-compose logs -f

# View logs for specific service (e.g., litellm, db, ollama)
docker-compose logs -f litellm

# Rebuild a specific service (e.g., after changes to Dockerfile.litellm)
docker-compose build litellm && docker-compose up -d litellm

# Restart a service
docker-compose restart litellm
```

### Database Access

```bash
# Connect to PostgreSQL directly
psql postgresql://llmproxy:${DB_PASSWORD}@localhost:5432/litellm

# View LiteLLM schema and data
\dt litellm.  # tables in litellm schema
```

### Testing LiteLLM API

```bash
# Health check
curl http://localhost:4000/health

# List available models
curl http://localhost:4000/v1/models

# Test a model call (replace model_name and adjust your API call)
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer ollama" \
  -H "Content-Type: application/json" \
  -d '{"model": "qwen3-14b-128k", "messages": [{"role": "user", "content": "Hello"}]}'
```

### Accessing LiteLLM UI

Open http://localhost:4000/ui in browser (login with UI_USERNAME and UI_PASSWORD from .env)

### Docker Commands for local-memory-mcp

```bash
# Run local-memory-mcp directly (for debugging)
docker exec ai_memory_mcp python3 src/postgres_memory_server.py

# View logs from local-memory-mcp
docker compose logs -f local-memory-mcp
```

## Configuration

### Model Configuration (config.yaml)

The `config.yaml` file defines available models. Each model entry:

```yaml
model_name: my-model           # Friendly name used in API calls
litellm_params:
  model: ollama_chat/model-id  # Provider/model format
  api_base: http://...         # API endpoint
  api_key: os.environ/VAR_NAME # Environment variable reference
```

**Model Types:**

- **Local Ollama**: `ollama_chat/<model-name>` with `api_base: http://192.168.1.132:11434`
- **Anthropic Local**: `anthropic/local` with `api_base: http://192.168.1.132:8080/v1/messages` (RTX 4080 rig)
- **Ollama Cloud**: `ollama_chat/<model>` with cloud api_base and api_key

**Adding a New Model:**

1. Pull the model in Ollama (if using local Ollama): `ollama pull model-name`
2. Add entry to config.yaml model_list
3. Restart LiteLLM: `docker-compose restart litellm`

### Environment Variables (.env)

```bash
OLLAMA_API_KEY       # Ollama Cloud API key (if using cloud models)
DB_PASSWORD          # PostgreSQL password (must match docker-compose.yml)
LITELLM_MASTER_KEY   # Master key for LiteLLM proxy auth
LITELLM_SALT_KEY     # Salt for encrypting stored API keys in LiteLLM DB
UI_USERNAME          # Username for LiteLLM UI
UI_PASSWORD          # Password for LiteLLM UI
```

## Database Schema

### PostgreSQL + pgvector

**Extensions:**
- `pgvector`: Vector similarity search (used by local-memory-mcp for semantic embeddings)

**Schema Ownership:**
- `litellm` schema: LiteLLM-managed tables
- `memory` schema: local-memory-mcp managed tables (created by docker-entrypoint-external.sh)

**initialization:**
- `init.sql`: Enables pgvector extension on first boot
- `local-memory-mcp/docker-entrypoint-external.sh`: Sets up memory-specific functions and schema

## Key Files and Their Purposes

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Defines all services and their configuration |
| `Dockerfile.litellm` | Custom LiteLLM image with docker-cli for MCP execution |
| `local-memory-mcp/Dockerfile` | Custom local-memory-mcp with external PostgreSQL support |
| `local-memory-mcp/docker-entrypoint-external.sh` | Initializes memory MCP with external PostgreSQL |
| `config.yaml` | LiteLLM model routing configuration |
| `init.sql` | Database initialization (pgvector extension) |
| `.env` | Environment variables for secrets and configuration |

## Troubleshooting

### PostgreSQL Connection Issues

```bash
# Check if db is healthy
docker-compose ps db

# Verify PostgreSQL is accepting connections
docker exec litellm_db pg_isready -U llmproxy -d litellm

# Check connection string format
# Expected: postgresql://llmproxy:PASSWORD@db:5432/litellm
```

### Ollama Service Issues

```bash
# Verify Ollama is running
curl http://localhost:11434/api/tags

# Check if embedding model is pulled
docker exec ai_ollama ollama list

# Pull embedding model if missing
docker exec ai_ollama ollama pull nomic-embed-text:latest
```

### LiteLLM Proxy Issues

```bash
# Check proxy health
curl http://localhost:4000/health

# Verify config is being loaded correctly
docker-compose logs litellm | grep "config.yaml"

# Test with specific model
curl -X POST http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer ollama" \
  -d '{"model": "gemma4-e4b-128k", "messages": [{"role": "user", "content": "test"}]}'
```

### local-memory-mcp Issues

```bash
# Test MCP directly
docker exec ai_memory_mcp python3 src/postgres_memory_server.py

# Check MCP logs
docker-compose logs -f local-memory-mcp

# Verify database connectivity from MCP
docker exec ai_memory_mcp psql -h db -U llmproxy -d litellm -c "SELECT 1"
```

## Development Workflow

### Making Changes to LiteLLM Configuration

1. Edit `config.yaml` with new models or settings
2. Restart LiteLLM: `docker-compose restart litellm`
3. Verify via API: `curl http://localhost:4000/v1/models`

### Making Changes to Docker Setup

1. Modify `docker-compose.yml` or Dockerfiles
2. Rebuild affected services: `docker-compose build [service]`
3. Restart: `docker-compose up -d`

### Database Schema Changes

1. Connect to PostgreSQL: `psql postgresql://llmproxy:${DB_PASSWORD}@localhost:5432/litellm`
2. Run migration scripts
3. Verify changes: `\dt litellm.` or `\dt memory.`

## Notes

- **RTX 4080 Rig**: Hosted externally at `192.168.1.132:8080` for `anthropic/local` model
- **Master Key**: Set to `"ollama"` in development (change for production!)
- **Fallback Master Key**: API requests can use `Authorization: Bearer ollama` as fallback
- **Database Password**: Must match between docker-compose.yml and .env
- **pgvector**: Enables vector similarity search; required for semantic memory operations
