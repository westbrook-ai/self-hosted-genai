# vLLM Production Stack — Testing & Troubleshooting

This document covers how to test and troubleshoot the vLLM deployment. For setup and configuration, see the [README](README.md).

## Testing the Deployment

### 1. Port Forward the Router Service

```bash
kubectl port-forward svc/vllm-tool-router-service -n genai 8000:80
```

### 2. List Available Models

```bash
curl http://localhost:8000/v1/models
```

Expected response:
```json
{
  "object": "list",
  "data": [
    {
      "id": "meta-llama/Llama-3.2-3B-Instruct",
      "object": "model",
      "created": 1234567890,
      "owned_by": "vllm"
    }
  ]
}
```

### 3. Test Completion Endpoint

```bash
curl -X POST http://localhost:8000/v1/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-3.2-3B-Instruct",
    "prompt": "Once upon a time,",
    "max_tokens": 50
  }'
```

### 4. Test Tool Calling

Create a test script `test_vllm_tools.py`:

```python
#!/usr/bin/env python3
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:8000/v1",
    api_key="not-needed"
)

tools = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get the current weather for a location",
            "parameters": {
                "type": "object",
                "properties": {
                    "location": {
                        "type": "string",
                        "description": "The city and state, e.g. San Francisco, CA"
                    },
                    "unit": {
                        "type": "string",
                        "enum": ["celsius", "fahrenheit"],
                        "description": "The temperature unit"
                    }
                },
                "required": ["location"]
            }
        }
    }
]

response = client.chat.completions.create(
    model="meta-llama/Llama-3.2-3B-Instruct",
    messages=[
        {"role": "user", "content": "What's the weather like in San Francisco?"}
    ],
    tools=tools,
    tool_choice="auto"
)

print("Response:")
print(response.choices[0].message)

if response.choices[0].message.tool_calls:
    print("\nTool calls detected!")
    for tool_call in response.choices[0].message.tool_calls:
        print(f"Function: {tool_call.function.name}")
        print(f"Arguments: {tool_call.function.arguments}")
```

Run the test:
```bash
pip install openai
python test_vllm_tools.py
```

## Troubleshooting

### Pods Not Starting

Check pod events:
```bash
kubectl describe pod -n genai -l app=vllm
```

Common issues:
- **Insufficient GPU** — Ensure GPU nodes are running and the NVIDIA device plugin is healthy
- **Image Pull Errors** — Verify network access and that the `vllm_tag` in `locals.tf` exists
- **OOM Errors** — Increase `vllm_request_memory` or reduce `vllm_max_model_len`
- **CUDA Driver Mismatch** — The `vllm_tag` must match the CUDA driver on the GPU AMI. Check `LD_LIBRARY_PATH` in `vllm.tf` if you see "unsupported display driver / cuda driver combination"

### Model Download Issues

Check logs for HuggingFace authentication errors:
```bash
kubectl logs -n genai -l model=llama3-3b
```

Verify the secret exists:
```bash
kubectl get secret huggingface-credentials -n genai
```

Ensure you've accepted the model license on HuggingFace and that your token has `read` access.

### Service Connection Issues

Verify services and endpoints:
```bash
kubectl get svc,endpoints -n genai
```

Test from within the cluster:
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -n genai -- \
  curl http://vllm-tool-router-service/v1/models
```

### Router Not Ready

The vLLM router needs the serving engine to be healthy before it will pass health checks. The startup probe allows up to 5 minutes for initial model loading. Check router logs:
```bash
kubectl logs -n genai -l app.kubernetes.io/component=router
```

## Resources

- [vLLM Documentation](https://docs.vllm.ai/)
- [vLLM Production Stack](https://docs.vllm.ai/projects/production-stack/)
- [Production Stack GitHub](https://github.com/vllm-project/production-stack)
- [Tool Calling Guide](https://docs.vllm.ai/projects/production-stack/en/latest/use_cases/tool-enabled-installation.html)
