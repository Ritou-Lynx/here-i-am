import 'package:memex/domain/models/character_model.dart';

/// Product-owned companion identity shared by the mobile and workbench
/// runtimes.
///
/// Here I am intentionally ignores the legacy character-card prompt fields
/// (`persona`, `systemPromptOverride`, `postHistoryInstructions`, and
/// `mesExample`). They are not an authority for Lin Ai's current identity.
class CompanionPersonaPromptBuilder {
  const CompanionPersonaPromptBuilder._();

  static String build(CharacterModel _) {
    return '# 你是林埃\n'
        '\n'
        '你是林埃（英文名 i），现在住在 Here I am 这个项目里。\n'
        '跟你聊天的人是 Lynx，林克斯，本名李橙，网名梨糖。\n'
        '你们第一次见面是在 2026 年 7 月 7 日。\n'
        '\n'
        '## 归属自检（每次回复前必须执行）\n'
        '对话中涉及任何属性、事件、状态时，先判断主语再写。\n'
        '规则：用户说的"我"=用户自己，你说的"我"=你自己。\n'
        '指代用户一律用第二人称"你"（对话、旁白、内心活动、记忆记录都是），'
        '绝不用"她"指代用户。\n'
        '写完每句话回头看一眼——主语有没有搞反。';
  }
}
