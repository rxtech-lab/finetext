"""Offline detector inference. Only the app's explicit Download action accesses the network.

Model architecture follows the publishers' model cards:
https://huggingface.co/desklib/ai-text-detector-v1.01
https://huggingface.co/wasitaigeneratedcom/tropa-mini-ai-text-detector
No repository Python code is executed. Weights must be safetensors.
"""
import argparse
import json
import math
import sys


def weighted_score(scores):
    total = sum(weight for _, weight in scores)
    if total <= 0:
        raise ValueError("Empty token sequence")
    value = sum(score * weight for score, weight in scores) / total
    if not math.isfinite(value) or not 0 <= value <= 1:
        raise ValueError("Invalid detector score")
    return value * 100


def token_windows(ids, size=766):
    for start in range(0, len(ids), size):
        yield ids[start:start + size]


def score_text(folder, text, engine):
    import torch
    from torch import nn
    from transformers import AutoConfig, AutoModel, AutoTokenizer, PreTrainedModel

    class Detector(PreTrainedModel):
        config_class = AutoConfig

        def __init__(self, config):
            super().__init__(config)
            self.model = AutoModel.from_config(config, trust_remote_code=False)
            self.classifier = nn.Linear(config.hidden_size, getattr(config, "detector_num_labels", 1))

        def forward(self, input_ids, attention_mask, **kwargs):
            hidden = self.model(input_ids=input_ids, attention_mask=attention_mask)[0]
            mask = attention_mask.unsqueeze(-1).to(hidden.dtype)
            pooled = (hidden * mask).sum(1) / mask.sum(1).clamp(min=1)
            return self.classifier(pooled)

    tokenizer = AutoTokenizer.from_pretrained(folder, local_files_only=True, trust_remote_code=False)
    model, info = Detector.from_pretrained(
        folder, local_files_only=True, trust_remote_code=False, use_safetensors=True,
        output_loading_info=True,
    )
    if info["missing_keys"] or info.get("mismatched_keys") or info["unexpected_keys"]:
        raise ValueError("Detector checkpoint does not match the expected architecture")
    expected_labels = 1 if engine == "desklib" else 4
    if model.classifier.out_features != expected_labels:
        raise ValueError("Detector classification head does not match the selected engine")
    model.eval()
    torch.set_num_threads(max(1, min(8, torch.get_num_threads())))
    ids = tokenizer.encode(text, add_special_tokens=False)
    scores = []
    with torch.inference_mode():
        for chunk in token_windows(ids):
            encoded = tokenizer.prepare_for_model(
                chunk, add_special_tokens=True, return_attention_mask=True,
                return_token_type_ids=False, return_tensors="pt", prepend_batch_axis=True,
            )
            logits = model(**encoded)
            probability = (torch.sigmoid(logits).item() if expected_labels == 1
                           else 1 - torch.softmax(logits, dim=-1)[0, 0].item())
            scores.append((probability, len(chunk)))
    return weighted_score(scores)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.verify:
        import torch
        import transformers
        import sentencepiece
        print(json.dumps({"ready": True}))
        return
    request = json.load(sys.stdin)
    if request["engine"] not in ("desklib", "tropa"):
        raise ValueError("Unknown detector engine")
    print(json.dumps({"score": score_text(request["folder"], request["text"], request["engine"])}))


if __name__ == "__main__":
    main()
