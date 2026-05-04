-- Create litellm database if it doesn't exist
SELECT 'CREATE DATABASE litellm OWNER llmproxy'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'litellm')\gexec

-- Create memory_mcp database if it doesn't exist  
SELECT 'CREATE DATABASE memory_mcp OWNER llmproxy'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'memory_mcp')\gexec

-- Grant access to both
GRANT ALL PRIVILEGES ON DATABASE litellm TO llmproxy;
GRANT ALL PRIVILEGES ON DATABASE memory_mcp TO llmproxy;

-- Enable pgvector extension on first boot
-- Both LiteLLM and mem0 use separate tables within the same DB
\c litellm
CREATE EXTENSION IF NOT EXISTS vector;

\c memory_mcp
CREATE EXTENSION IF NOT EXISTS vector;
