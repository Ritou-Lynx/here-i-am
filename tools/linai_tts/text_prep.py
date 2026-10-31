"""把伴侣 Agent 的回复整理成 Chatterbox-Turbo 能直接念的英文文本。

只保留 Turbo tokenizer 认识的副语言标签，其余方括号、*动作*、括号里的舞台说明一律删掉，
免得模型把它们逐字念出来。纯函数，不依赖模型，可单测。
"""
import re

ALLOWED_TAGS = frozenset({
    "laugh", "chuckle", "sigh", "gasp", "cough", "clear throat", "crying", "sniff",
    "groan", "shush", "whispering", "happy", "angry", "sarcastic", "surprised", "fear", "dramatic",
})

_BRACKET = re.compile(r"\[([^\[\]]*)\]")
_ACTION = re.compile(r"\*[^*]*\*")
_PAREN = re.compile(r"\([^()]*\)|（[^（）]*）")
_SPACE = re.compile(r"\s+")
_SPACE_BEFORE_PUNCT = re.compile(r"\s+([,.!?;:])")


class TextError(ValueError):
    """文本不可合成；code 用于响应和日志，不含原文。"""

    def __init__(self, code):
        super().__init__(code)
        self.code = code


def _keep_allowed(match):
    tag = _SPACE.sub(" ", match.group(1).strip().lower())
    return f" [{tag}] " if tag in ALLOWED_TAGS else " "


def prepare_text(text, max_chars=400):
    if not isinstance(text, str) or not text.strip():
        raise TextError("empty_text")
    text = text.strip()
    if len(text) > max_chars:
        raise TextError("text_too_long")
    text = _ACTION.sub(" ", text)
    text = _PAREN.sub(" ", text)
    text = _BRACKET.sub(_keep_allowed, text)
    text = _SPACE.sub(" ", text).strip()
    text = _SPACE_BEFORE_PUNCT.sub(r"\1", text)
    if not text or not _BRACKET.sub("", text).strip(" ,.!?;:"):
        raise TextError("empty_after_cleanup")
    return text
