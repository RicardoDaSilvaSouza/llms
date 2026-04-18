-- Enable pgvector extension on first boot
-- Both LiteLLM and mem0 use separate tables within the same DB
CREATE EXTENSION IF NOT EXISTS vector;
