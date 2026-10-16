# panels-dictation-1

Small on-device models that turn raw speech into clean text that fits the field you are typing in. Everything runs on the Mac, nothing leaves it.

## Pieces

| Piece | Job | Target size |
| --- | --- | --- |
| Voice detector | starts and stops phrases | about 2 MB |
| Speech to text | Apple SpeechAnalyzer, built into macOS | 0 MB |
| Edit tagger | punctuation, capitals, delete fillers and false starts | 30 to 60 MB |
| Language model base | formatting, commands, vocabulary, self corrections | about 350 MB at 4 bit |
| Adapter: refine | field aware cleanup | 10 to 20 MB |
| Adapter: live revise | corrects earlier words as you keep talking | 10 to 20 MB |

## What exists

- `gen_data.py` builds 33,000 raw to clean examples (train, valid, and a held-out test set with names and topics the training data never sees). Each record carries the field mode (note, markdown, terminal), the text already before the caret, the user's vocabulary, the raw transcript and the clean target.
- `eval.py` scores any cleaner on the test set. Baselines today: raw speech 2.1 percent exact, the rules shipped in the app 5.1 percent exact.

```bash
python3 ml/gen_data.py
python3 ml/eval.py
```

## Next, needs approval to download

1. A Python virtual environment with `mlx-lm` 0.32.2 and its dependencies (mlx, numpy, transformers, sentencepiece, protobuf, pyyaml, jinja2, plus datasets and tqdm for training).
2. One base model from Hugging Face, `mlx-community/Qwen3-0.6B-4bit` (351 MB). A 1B alternative, `mlx-community/gemma-3-1b-it-4bit`, is 772 MB.

Then: baseline the untuned model on the test set, LoRA fine tune on `data/train.jsonl`, fuse and quantize, re-score, and wire the winner into the app with MLX Swift.
