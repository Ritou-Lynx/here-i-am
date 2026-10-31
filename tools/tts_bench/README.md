# Chatterbox-Turbo 分段测速（临时分支，不合并）

- `profile_turbo.py`：给 T3（出 token）、S3Gen（出波形）、水印三段计时，并在生成期间采样 GPU 利用率、频率、功耗；跑 baseline / 去水印 / T3 bf16 三个变体，结果写入当前目录的 `profile.json`。
- `linai-ref-v5.wav`：林埃声音 5 的参考音频（CSM-1B 生成，12 秒）。

用法：把两个文件复制到装好 chatterbox 的测速 venv 目录，运行 `python profile_turbo.py --ref linai-ref-v5.wav`。
