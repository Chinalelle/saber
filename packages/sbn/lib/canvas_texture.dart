/// 画布表面的质感（无边画布的可选预设之一）。
enum CanvasTexture(
  /// 序列化用的名字。别直接展示给用户。
  final String name,
) {
  /// 光滑（默认）
  smooth(''),

  /// 纸张：带一点点起伏和颗粒，看起来像真的纸
  paper('paper');

  /// 从序列化名字还原，认不出来就退回默认值。
  static CanvasTexture fromName(String? name) => CanvasTexture.values
      .firstWhere((texture) => texture.name == name, orElse: () => smooth);
}
