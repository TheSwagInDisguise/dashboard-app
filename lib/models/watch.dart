// Watch, wear, strap and service records. All metadata is syncable; photos
// remain device-local in WatchPhotoStore.

DateTime _watchParseTime(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toUtc() ??
    DateTime.now().toUtc();
String _watchDateKey(int epochDay) {
  final d = DateTime(1970, 1, 1).add(Duration(days: epochDay));
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class Watch {
  Watch({
    required this.id,
    required this.brand,
    required this.model,
    this.nickname = '',
    this.reference = '',
    this.movement = '',
    this.caseSizeMm,
    this.color = 'cyan',
    this.notes = '',
    this.status = statusOwned,
    this.archived = false,
    this.serviceIntervalMonths = 0,
    this.purchaseDay,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  static const String statusOwned = 'owned';
  static const String statusRepair = 'repair';
  static const String statusSold = 'sold';
  static const String statusWishlist = 'wishlist';

  final String id;
  final String brand;
  final String model;
  final String nickname;
  final String reference;
  final String movement;
  final double? caseSizeMm;
  final String color;
  final String notes;
  final String status;
  final bool archived;

  /// Recommended service interval in calendar months; zero means untracked.
  final int serviceIntervalMonths;

  /// Optional purchase date as epoch day.
  final int? purchaseDay;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get deleted => deletedAt != null;
  bool get owned =>
      !archived && (status == statusOwned || status == statusRepair);
  String get displayName {
    final nick = nickname.trim();
    if (nick.isNotEmpty) return nick;
    final full = '$brand $model'.trim();
    return full.isEmpty ? 'watch' : full;
  }

  Watch copyWith({
    String? brand,
    String? model,
    String? nickname,
    String? reference,
    String? movement,
    double? caseSizeMm,
    bool clearCaseSizeMm = false,
    String? color,
    String? notes,
    String? status,
    bool? archived,
    int? serviceIntervalMonths,
    int? purchaseDay,
    bool clearPurchaseDay = false,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => Watch(
    id: id,
    brand: brand ?? this.brand,
    model: model ?? this.model,
    nickname: nickname ?? this.nickname,
    reference: reference ?? this.reference,
    movement: movement ?? this.movement,
    caseSizeMm: clearCaseSizeMm ? null : (caseSizeMm ?? this.caseSizeMm),
    color: color ?? this.color,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    archived: archived ?? this.archived,
    serviceIntervalMonths: serviceIntervalMonths ?? this.serviceIntervalMonths,
    purchaseDay: clearPurchaseDay ? null : (purchaseDay ?? this.purchaseDay),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'brand': brand,
    'model': model,
    'nickname': nickname,
    'reference': reference,
    'movement': movement,
    'caseSizeMm': caseSizeMm,
    'color': color,
    'notes': notes,
    'status': status,
    'archived': archived,
    'serviceIntervalMonths': serviceIntervalMonths,
    'purchaseDay': purchaseDay,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };

  factory Watch.fromJson(Map<String, dynamic> json) => Watch(
    id: json['id']?.toString() ?? '',
    brand: json['brand']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
    nickname: json['nickname']?.toString() ?? '',
    reference: json['reference']?.toString() ?? '',
    movement: json['movement']?.toString() ?? '',
    caseSizeMm: (json['caseSizeMm'] as num?)?.toDouble(),
    color: json['color']?.toString() ?? 'cyan',
    notes: json['notes']?.toString() ?? '',
    status: json['status']?.toString() ?? statusOwned,
    archived: json['archived'] == true,
    serviceIntervalMonths:
        (json['serviceIntervalMonths'] as num?)?.toInt() ?? 0,
    purchaseDay: (json['purchaseDay'] as num?)?.toInt(),
    createdAt: _watchParseTime(json['createdAt']),
    updatedAt: _watchParseTime(json['updatedAt']),
    deletedAt: json['deletedAt'] == null
        ? null
        : _watchParseTime(json['deletedAt']),
  );
}

class WearLog {
  WearLog({
    required this.id,
    required this.watchId,
    required this.day,
    this.note = '',
    this.strapId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String watchId;
  final int day;
  final String note;
  final String? strapId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  bool get deleted => deletedAt != null;

  Map<String, dynamic> toJson() => {
    'id': id,
    'watchId': watchId,
    'day': day,
    'date': _watchDateKey(day),
    'note': note,
    'strapId': strapId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };

  factory WearLog.fromJson(Map<String, dynamic> json) {
    var day = (json['day'] as num?)?.toInt();
    if (day == null && json['date'] != null) {
      final d = DateTime.tryParse(json['date'].toString());
      if (d != null) {
        day = DateTime(
          d.year,
          d.month,
          d.day,
        ).difference(DateTime(1970, 1, 1)).inDays;
      }
    }
    return WearLog(
      id: json['id']?.toString() ?? '',
      watchId: json['watchId']?.toString() ?? '',
      day: day ?? 0,
      note: json['note']?.toString() ?? '',
      strapId: json['strapId']?.toString(),
      createdAt: _watchParseTime(json['createdAt']),
      updatedAt: _watchParseTime(json['updatedAt']),
      deletedAt: json['deletedAt'] == null
          ? null
          : _watchParseTime(json['deletedAt']),
    );
  }
}

class Strap {
  Strap({
    required this.id,
    required this.name,
    this.material = '',
    this.color = '',
    this.widthMm,
    this.watchId,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  final String id;
  final String name;
  final String material;
  final String color;
  final int? widthMm;
  final String? watchId;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  bool get deleted => deletedAt != null;

  Strap copyWith({
    String? name,
    String? material,
    String? color,
    int? widthMm,
    String? watchId,
    bool clearWatchId = false,
    String? notes,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => Strap(
    id: id,
    name: name ?? this.name,
    material: material ?? this.material,
    color: color ?? this.color,
    widthMm: widthMm ?? this.widthMm,
    watchId: clearWatchId ? null : (watchId ?? this.watchId),
    notes: notes ?? this.notes,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'material': material,
    'color': color,
    'widthMm': widthMm,
    'watchId': watchId,
    'notes': notes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };
  factory Strap.fromJson(Map<String, dynamic> j) => Strap(
    id: j['id']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    material: j['material']?.toString() ?? '',
    color: j['color']?.toString() ?? '',
    widthMm: (j['widthMm'] as num?)?.toInt(),
    watchId: j['watchId']?.toString(),
    notes: j['notes']?.toString() ?? '',
    createdAt: _watchParseTime(j['createdAt']),
    updatedAt: _watchParseTime(j['updatedAt']),
    deletedAt: j['deletedAt'] == null ? null : _watchParseTime(j['deletedAt']),
  );
}

class StrapSwap {
  StrapSwap({
    required this.id,
    required this.strapId,
    this.watchId,
    required this.day,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  final String id;
  final String strapId;
  final String? watchId;
  final int day;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  bool get deleted => deletedAt != null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'strapId': strapId,
    'watchId': watchId,
    'day': day,
    'date': _watchDateKey(day),
    'note': note,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };
  factory StrapSwap.fromJson(Map<String, dynamic> j) {
    var day = (j['day'] as num?)?.toInt();
    if (day == null && j['date'] != null) {
      final d = DateTime.tryParse(j['date'].toString());
      if (d != null) {
        day = DateTime(
          d.year,
          d.month,
          d.day,
        ).difference(DateTime(1970, 1, 1)).inDays;
      }
    }
    return StrapSwap(
      id: j['id']?.toString() ?? '',
      strapId: j['strapId']?.toString() ?? '',
      watchId: j['watchId']?.toString(),
      day: day ?? 0,
      note: j['note']?.toString() ?? '',
      createdAt: _watchParseTime(j['createdAt']),
      updatedAt: _watchParseTime(j['updatedAt']),
      deletedAt: j['deletedAt'] == null
          ? null
          : _watchParseTime(j['deletedAt']),
    );
  }
}

class WatchService {
  WatchService({
    required this.id,
    required this.watchId,
    required this.day,
    this.kind = 'service',
    this.description = '',
    this.cost,
    this.currency = '',
    this.nextDueDay,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  final String id;
  final String watchId;
  final int day;
  final String kind;
  final String description;
  final double? cost;
  final String currency;
  final int? nextDueDay;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  bool get deleted => deletedAt != null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'watchId': watchId,
    'day': day,
    'date': _watchDateKey(day),
    'kind': kind,
    'description': description,
    'cost': cost,
    'currency': currency,
    'nextDueDay': nextDueDay,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };
  factory WatchService.fromJson(Map<String, dynamic> j) {
    var day = (j['day'] as num?)?.toInt();
    if (day == null && j['date'] != null) {
      final d = DateTime.tryParse(j['date'].toString());
      if (d != null) {
        day = DateTime(
          d.year,
          d.month,
          d.day,
        ).difference(DateTime(1970, 1, 1)).inDays;
      }
    }
    return WatchService(
      id: j['id']?.toString() ?? '',
      watchId: j['watchId']?.toString() ?? '',
      day: day ?? 0,
      kind: j['kind']?.toString() ?? 'service',
      description: j['description']?.toString() ?? '',
      cost: (j['cost'] as num?)?.toDouble(),
      currency: j['currency']?.toString() ?? '',
      nextDueDay: (j['nextDueDay'] as num?)?.toInt(),
      createdAt: _watchParseTime(j['createdAt']),
      updatedAt: _watchParseTime(j['updatedAt']),
      deletedAt: j['deletedAt'] == null
          ? null
          : _watchParseTime(j['deletedAt']),
    );
  }
}
