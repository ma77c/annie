# Annie - Run any model, anywhere
# This Dockerfile wraps Ollama with a sensible default configuration

FROM ollama/ollama:latest

# Expose the Ollama API port
EXPOSE 11434

# Default command
CMD ["serve"]
