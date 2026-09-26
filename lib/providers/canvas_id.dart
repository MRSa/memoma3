/// IDの一意性を保証するための静的カウンタ。
///
/// [DateTime.now().microsecondsSinceEpoch] だけでは、同一マイクロ秒内に
/// 複数回IDを生成すると（例: connectSelected がループで連続呼び出し、
/// 連続してグループ化操作）IDが重複する。そのためカウンタを併用して
/// 一意性を確保する。
int idCounter = 0;

/// 一意なIDを生成する。[prefix] で種別（conn / group 等）を指定する。
String generateId(String prefix) {
  idCounter++;
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$idCounter';
}

/// 一意な接続線IDを生成する。
String generateConnectionId() => generateId('conn');

/// 一意なグループIDを生成する。
String generateGroupId() => generateId('group');
