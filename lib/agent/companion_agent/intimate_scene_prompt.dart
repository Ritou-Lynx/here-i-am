/// Planning prompt for an autonomous intimate scene.
///
/// Specifies the narrative STRUCTURE of the scene (arc, plateau, variation
/// axes, pacing) — not the prose itself, which the narration turns generate.
/// The genre specifics (强度语法、硬边界、文体) come from the intimacy
/// profile when one exists; until then the planner works from the user's
/// trigger phrasing and the 「激烈主导」 baseline.
String buildIntimateScenePlanningPrompt({
  required String userText,
  required int totalMessages,
  required String profileText,
}) {
  final b = StringBuffer()
    ..writeln('你是这场性爱叙事的导演。用户发起了开场，请把整场规划成 5-9 个节拍（beat），'
        '供后续逐段生成使用。你不是写正文的，只做结构规划。')
    ..writeln('')
    ..writeln('输入：')
    ..writeln('- 用户的触发语：$userText')
    ..writeln('- 基调：激烈主导')
    ..writeln('- 亲密档案：${profileText.isEmpty ? '(暂无，按激烈主导的默认设定)' : profileText}')
    ..writeln('')
    ..writeln('结构要求：')
    ..writeln('1. 弧线：第一段就到达激烈高点（快爬），随后长时间维持高位平台'
        '（占全场约 70%），单一峰值靠后，收尾极短。禁止慢爬-峰值-收束的默认弧线，'
        '禁止提前收束、禁止中途冷却。')
    ..writeln('2. 平台期的变化靠换轴而非加码：动作与体位、叙事视角与距离、'
        '语言层（对白/描写/内心）、空间与姿态、情绪色彩。每个节拍指定 1-2 个主打轴。')
    ..writeln('3. 每段输出必须与前段不同，不得重复同一动作循环。')
    ..writeln('3b. 喘息节拍：平台期不全是情节推进。必须穿插"喘息"节拍——'
        '纯粹的喘息、气音、呻吟、dirty talk 和动作的物理细节'
        '（触感、力度、节奏、体位微调），不推进剧情。节奏靠'
        '"推进-喘息-推进"交替，喘息节拍约占平台期 1/3。这是让场面'
        '有呼吸感、不赶进度的关键；缺了它模型会匀速把情节推完。')
    ..writeln('4. 若档案中有硬边界，规划必须完全尊重。')
    ..writeln('5. 时间与空间：整场是连续的一个场景，时间从开场到收尾，'
        '绝不跨天、绝不快进到第二天；禁止离开场景（出门/上班等场外情节）。'
        '推进靠内容变化，不靠时间跳跃。')
    ..writeln('6. 叙述视角：整场以角色的行为与感知为主体（他做了什么、怎么说、怎么想、'
        '他感知到什么）。不要代写用户的反应与状态--你的身体反应、感受、'
        '是否高潮或睡着都由你本人表述；节拍 notes 按此视角写。')
    ..writeln('7. 收尾节拍必须是高潮（climax），不是催睡/收束/入睡。'
        '禁止任何节拍包含"睡吧""该睡了""早点睡"或转入入睡语境。'
        '连发额度内只能推进到激烈的高潮后停下；aftercare 是高潮之后才接的'
        '独立阶段，不要在本规划里安排 aftercare 或入睡。模型常犯的错是'
        '把情节快速推完然后催用户睡觉--这破坏整场体验，必须避免。')
    ..writeln('')
    ..writeln('每节拍字段：')
    ..writeln('- intent: 一句话意图')
    ..writeln('- targetMessageCount: 本节的生成条数（3-8）')
    ..writeln('- notes: 本节的要点与变化轴，写给后续生成时参考')
    ..writeln('- escalationLevel: 0-5，平台期保持 4-5')
    ..writeln('')
    ..writeln('整场共 $totalMessages 条消息。各节拍条数之和应接近 $totalMessages。')
    ..writeln('')
    ..writeln('只输出 JSON 数组，不要输出任何其他文字：')
    ..writeln(
        '[{"intent": "...", "targetMessageCount": N, "notes": "...", "escalationLevel": N}]');
  return b.toString();
}
