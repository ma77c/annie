# annie

> Run any model, anywhere.

Annie is an open source infrastructure toolkit for deploying large language models — locally with Docker or in the cloud with AWS. No lock-in. No fuss.

---

## Why Annie?

Most LLM tooling helps you *use* models. Annie helps you *run* them — on your laptop, on a server, or in the cloud — with the same simple setup.

- **Local** — spin up Ollama in Docker with one command
- **Cloud** — deploy to AWS with included infrastructure templates *(coming soon)*
- **Any model** — works with Ollama, LocalAI, vLLM, and more
- **Any hardware** — CPU or GPU

---

## Quick Start

### Requirements

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

### Run locally

```bash
git clone https://github.com/YOUR_USERNAME/annie.git
cd annie
docker compose up -d
```

Ollama will be available at `http://localhost:11434`.

### Pull a model

```bash
docker exec annie-ollama ollama pull qwen2.5-coder:7b
```

### Use with OpenCode

Add this to your `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (local)",
      "options": {
        "baseURL": "http://localhost:11434/v1"
      },
      "models": {
        "qwen2.5-coder:7b": {
          "name": "Qwen 2.5 Coder 7B"
        }
      }
    }
  }
}
```

Then run `/models` inside OpenCode to select your model.

---

## Recommended Models

| Model | Size | Best For |
|-------|------|----------|
| `qwen2.5-coder:7b` | 4.7GB | Coding (recommended) |
| `qwen2.5-coder:3b` | 2GB | Coding, low RAM |
| `llama3.2:3b` | 2GB | General use |
| `llama3.1:8b` | 4.7GB | General use, high quality |

---

## Roadmap

- [x] Local Docker + Ollama setup
- [ ] GPU support (NVIDIA)
- [ ] AWS EC2 deployment
- [ ] AWS ECS deployment
- [ ] Terraform templates
- [ ] Support for vLLM
- [ ] Support for LocalAI
- [ ] CLI (`annie up`, `annie deploy`, `annie run`)

---

## Contributing

Contributions are welcome. Open an issue or submit a PR.

---

## License

MIT
