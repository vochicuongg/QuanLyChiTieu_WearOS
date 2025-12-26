import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';


// Global SharedPreferences instance for faster access
SharedPreferences? _prefs;

// Global language setting - 'vi' for Vietnamese, 'en' for English
String _appLanguage = 'vi';
const String _keyLanguage = 'app_language';

// Global currency setting - 'đ' for VND, '$' for USD
String _appCurrency = 'đ';
const String _keyCurrency = 'app_currency';

// Global exchange rate (VND to USD) - default fallback rate
double _exchangeRate = 0.00004; // ~1 USD = 25,000 VND
const String _keyExchangeRate = 'exchange_rate';
bool _isLoadingRate = false;

// Cached regex for number formatting - avoid creating new RegExp on every call
final RegExp _numberFormatRegex = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');

// Pre-built theme for faster startup - avoid creating new ThemeData each time
final ThemeData _appTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: Colors.black,
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
    },
  ),
);

void main() {
  // Preserve splash screen while app initializes
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  // Start SharedPreferences loading in background (non-blocking)
  SharedPreferences.getInstance().then((prefs) => _prefs = prefs);
  
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VFinance',
      theme: _appTheme,
      home: const ChiTieuApp(),
    ),
  );
}

// =================== UTILS ===================

String dinhDangSo(int value) {
  return value.toString().replaceAllMapped(
    _numberFormatRegex,
    (m) => '${m[1]}.',
  );
}

String dinhDangGio(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// Internal date key format - ALWAYS DD/MM/YYYY for consistent storage
String dinhDangNgayDayDu(DateTime time) {
  final d = time.day.toString().padLeft(2, '0');
  final mo = time.month.toString().padLeft(2, '0');
  final y = time.year.toString(); // 4-digit year for consistency with Kotlin Tile/Complication
  return '$d/$mo/$y';
}

// Display date format - localized for UI display only
String dinhDangNgayHienThi(DateTime time) {
  final d = time.day.toString().padLeft(2, '0');
  final mo = time.month.toString().padLeft(2, '0');
  final y = time.year.toString(); // 4-digit year for consistency
  if (_appLanguage == 'en') {
    return '$mo/$d/$y';
  }
  return '$d/$mo/$y';
}

// Get ordinal suffix for English (1st, 2nd, 3rd, 4th, etc.)
String getOrdinalSuffix(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  switch (day % 10) {
    case 1: return '${day}st';
    case 2: return '${day}nd';
    case 3: return '${day}rd';
    default: return '${day}th';
  }
}

// Get month name for English
String getMonthName(int month) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return months[month - 1];
}

// Get short month name for English
String getShortMonthName(int month) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return months[month - 1];
}

String getMonthKey(DateTime date) => '${date.month}/${date.year}';

// =================== CURRENCY CONVERSION ===================

// Fetch real-time exchange rate from ExchangeRate-API (free, no auth)
Future<double> fetchExchangeRate() async {
  try {
    _isLoadingRate = true;
    final response = await http.get(
      Uri.parse('https://open.er-api.com/v6/latest/VND'),
    ).timeout(const Duration(seconds: 10));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final usdRate = data['rates']['USD'];
      if (usdRate != null) {
        _exchangeRate = (usdRate as num).toDouble();
        // Cache the rate
        final prefs = _prefs ?? await SharedPreferences.getInstance();
        await prefs.setDouble(_keyExchangeRate, _exchangeRate);
      }
    }
  } catch (e) {
    // Use cached or default rate on error
    debugPrint('Exchange rate fetch failed: $e');
  } finally {
    _isLoadingRate = false;
  }
  return _exchangeRate;
}

// Convert VND amount to display value based on currency setting
int convertAmount(int vndAmount) {
  if (_appCurrency == 'đ') return vndAmount;
  // Convert to USD - no rounding
  return (vndAmount * _exchangeRate).toInt();
}

// Format amount with currency symbol - no rounding
String formatAmountWithCurrency(int vndAmount) {
  if (_appCurrency == 'đ') {
    return '${dinhDangSo(vndAmount)} đ';
  } else {
    // Always show exact USD amount with 2 decimal places and comma separators
    final usdDouble = vndAmount * _exchangeRate;
    return '\$${_formatUsdWithCommas(usdDouble)}';
  }
}

// Format USD with commas as thousand separators and 2 decimal places (e.g., 2,294.69)
String _formatUsdWithCommas(double amount) {
  // Split into integer and decimal parts
  final intPart = amount.truncate();
  final decimalPart = ((amount - intPart) * 100).round();
  
  // Format integer part with commas
  final intStr = intPart.toString().replaceAllMapped(
    _numberFormatRegex,
    (m) => '${m[1]},',
  );
  
  // Format decimal part with leading zero if needed
  final decStr = decimalPart.toString().padLeft(2, '0');
  
  return '$intStr.$decStr';
}

// =================== CLOCK ===================

class ClockText extends StatefulWidget {
  final TextStyle? style;
  final bool showSeconds;

  const ClockText({super.key, this.style, this.showSeconds = false});

  @override
  State<ClockText> createState() => _ClockTextState();
}

class _ClockTextState extends State<ClockText> {
  late Timer _timer;
  DateTime _now = DateTime.now();
  int _lastMinute = -1;

  String _two(int n) => n.toString().padLeft(2, '0');

  String get _timeText {
    final h = _two(_now.hour);
    final m = _two(_now.minute);
    if (!widget.showSeconds) return '$h:$m';
    final s = _two(_now.second);
    return '$h:$m:$s';
  }

  @override
  void initState() {
    super.initState();
    _lastMinute = _now.minute;
    // Update every minute if not showing seconds, every second otherwise
    final interval = widget.showSeconds ? const Duration(seconds: 1) : const Duration(seconds: 10);
    _timer = Timer.periodic(interval, (_) {
      final now = DateTime.now();
      // Only rebuild if minute changed (or second changed when showing seconds)
      if (widget.showSeconds || now.minute != _lastMinute) {
        _lastMinute = now.minute;
        if (mounted) setState(() => _now = now);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _timeText,
      style: widget.style ??
          const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
      textAlign: TextAlign.center,
    );
  }
}

// =================== MODEL ===================

class ChiTieuItem {
  final int soTien;
  final DateTime thoiGian;
  final String? tenChiTieu; // Optional expense name for khac category

  ChiTieuItem({
    required this.soTien,
    required this.thoiGian,
    this.tenChiTieu,
  });

  ChiTieuItem copyWith({int? soTien, DateTime? thoiGian, String? tenChiTieu}) {
    return ChiTieuItem(
      soTien: soTien ?? this.soTien,
      thoiGian: thoiGian ?? this.thoiGian,
      tenChiTieu: tenChiTieu ?? this.tenChiTieu,
    );
  }

  Map<String, dynamic> toJson() => {
    'soTien': soTien,
    'thoiGian': thoiGian.toIso8601String(),
    if (tenChiTieu != null) 'tenChiTieu': tenChiTieu,
  };

  factory ChiTieuItem.fromJson(Map<String, dynamic> json) => ChiTieuItem(
    soTien: json['soTien'] as int,
    thoiGian: DateTime.parse(json['thoiGian'] as String),
    tenChiTieu: json['tenChiTieu'] as String?,
  );
}

// =================== CATEGORY ===================

enum ChiTieuMuc { soDu, nhaTro, hocPhi, thucAn, doUong, xang, muaSam, suaXe, khac, lichSu, caiDat }

extension ChiTieuMucX on ChiTieuMuc {
  String get ten {
    final isVi = _appLanguage == 'vi';
    switch (this) {
      case ChiTieuMuc.soDu:
        return isVi ? 'Số dư' : 'Balance';
      case ChiTieuMuc.nhaTro:
        return isVi ? 'Nhà trọ' : 'Rent';
      case ChiTieuMuc.hocPhi:
        return isVi ? 'Học phí' : 'Tuition';
      case ChiTieuMuc.thucAn:
        return isVi ? 'Thức ăn' : 'Food';
      case ChiTieuMuc.doUong:
        return isVi ? 'Đồ uống' : 'Drinks';
      case ChiTieuMuc.xang:
        return isVi ? 'Xăng' : 'Gas';
      case ChiTieuMuc.muaSam:
        return isVi ? 'Mua sắm' : 'Shopping';
      case ChiTieuMuc.suaXe:
        return isVi ? 'Sửa xe' : 'Repair';
      case ChiTieuMuc.khac:
        return isVi ? 'Khoản chi khác' : 'Other';
      case ChiTieuMuc.lichSu:
        return isVi ? 'Lịch sử' : 'History';
      case ChiTieuMuc.caiDat:
        return isVi ? 'Cài đặt' : 'Settings';
    }
  }

  IconData get icon {
    switch (this) {
      case ChiTieuMuc.soDu:
        return Icons.account_balance_wallet_rounded;
      case ChiTieuMuc.nhaTro:
        return Icons.home_rounded;
      case ChiTieuMuc.hocPhi:
        return Icons.school_rounded;
      case ChiTieuMuc.thucAn:
        return Icons.restaurant_rounded;
      case ChiTieuMuc.doUong:
        return Icons.local_cafe_rounded;
      case ChiTieuMuc.xang:
        return Icons.local_gas_station_rounded;
      case ChiTieuMuc.muaSam:
        return Icons.shopping_bag_rounded;
      case ChiTieuMuc.suaXe:
        return Icons.build_rounded;
      case ChiTieuMuc.khac:
        return Icons.money_rounded;
      case ChiTieuMuc.lichSu:
        return Icons.history_rounded;
      case ChiTieuMuc.caiDat:
        return Icons.settings_rounded;
    }
  }
}

// Simplified background for faster rendering
class _WatchBackground extends StatelessWidget {
  const _WatchBackground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: Colors.black);
  }
}

// =================== HELPER ===================

class HistoryEntry {
  final ChiTieuMuc muc;
  final ChiTieuItem item;
  HistoryEntry({required this.muc, required this.item});
}

// =================== HOME (GRID CATEGORIES) ===================

class ChiTieuApp extends StatefulWidget {
  const ChiTieuApp({super.key});

  @override
  State<ChiTieuApp> createState() => _ChiTieuAppState();
}

class _ChiTieuAppState extends State<ChiTieuApp> {
  DateTime _currentDay = _asDate(DateTime.now());
  final SmoothScrollController _scrollAnimController = SmoothScrollController();
  bool _isLoading = true; // Track loading state for faster initial render

  final Map<ChiTieuMuc, List<ChiTieuItem>> _chiTheoMuc = {
    for (final muc in ChiTieuMuc.values) muc: <ChiTieuItem>[],
  };

  final Map<String, Map<String, List<HistoryEntry>>> _lichSuThang = {};

  static const String _keyChiTheoMuc = 'chi_theo_muc';
  static const String _keyLichSuThang = 'lich_su_thang';

  // Cached values for performance
  int? _cachedTongHomNay;
  final Map<ChiTieuMuc, int> _cachedTongMuc = {};
  Timer? _dayCheckTimer;

  static DateTime _asDate(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // Get Vietnamese category name with diacritics for Tile
  String _getCategoryNameVi(ChiTieuMuc muc) {
    switch (muc) {
      case ChiTieuMuc.nhaTro: return 'Nhà trọ';
      case ChiTieuMuc.hocPhi: return 'Học phí';
      case ChiTieuMuc.thucAn: return 'Thức ăn';
      case ChiTieuMuc.doUong: return 'Đồ uống';
      case ChiTieuMuc.xang: return 'Xăng';
      case ChiTieuMuc.muaSam: return 'Mua sắm';
      case ChiTieuMuc.suaXe: return 'Sửa xe';
      case ChiTieuMuc.khac: return 'Khác';
      default: return muc.name;
    }
  }

  void _invalidateCache() {
    _cachedTongHomNay = null;
    _cachedTongMuc.clear();
  }

  @override
  void initState() {
    super.initState();
    // Defer data loading to after first frame for faster initial render
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
    _dayCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkNewDay());
  }

  @override
  void dispose() {
    _dayCheckTimer?.cancel();
    _scrollAnimController.dispose();
    super.dispose();
  }

  // Load data from SharedPreferences (uses pre-cached instance)
  Future<void> _loadData() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    
    // Load language preference first
    final savedLanguage = prefs.getString(_keyLanguage);
    if (savedLanguage != null) {
      _appLanguage = savedLanguage;
    }
    
    // Load currency preference
    final savedCurrency = prefs.getString(_keyCurrency);
    if (savedCurrency != null) {
      _appCurrency = savedCurrency;
    }
    
    // Load cached exchange rate
    final savedExchangeRate = prefs.getDouble(_keyExchangeRate);
    if (savedExchangeRate != null) {
      _exchangeRate = savedExchangeRate;
    }
    
    // Load _chiTheoMuc (including soDu for income tracking)
    final chiTheoMucJson = prefs.getString(_keyChiTheoMuc);
    if (chiTheoMucJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(chiTheoMucJson);
        for (final muc in ChiTieuMuc.values) {
          if (muc == ChiTieuMuc.lichSu || muc == ChiTieuMuc.caiDat) continue;
          final mucName = muc.name;
          if (decoded.containsKey(mucName)) {
            final List<dynamic> items = decoded[mucName];
            _chiTheoMuc[muc] = items
                .map((e) => ChiTieuItem.fromJson(e as Map<String, dynamic>))
                .toList();
          }
        }
      } catch (_) {}
    }
    
    // Load _lichSuThang
    final lichSuThangJson = prefs.getString(_keyLichSuThang);
    if (lichSuThangJson != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(lichSuThangJson);
        for (final monthKey in decoded.keys) {
          final Map<String, dynamic> daysData = decoded[monthKey];
          _lichSuThang[monthKey] = {};
          for (final dayKey in daysData.keys) {
            final List<dynamic> entries = daysData[dayKey];
            _lichSuThang[monthKey]![dayKey] = entries.map((e) {
              final mucName = e['muc'] as String;
              final muc = ChiTieuMuc.values.firstWhere((m) => m.name == mucName);
              final item = ChiTieuItem.fromJson(e['item'] as Map<String, dynamic>);
              return HistoryEntry(muc: muc, item: item);
            }).toList();
          }
        }
      } catch (_) {}
    }
    
    _invalidateCache();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      // Remove splash screen now that app is ready
      FlutterNativeSplash.remove();
    }
  }

  // Save data to SharedPreferences (uses pre-cached instance)
  Future<void> _saveData() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    
    // Save _chiTheoMuc (including soDu for income tracking)
    final Map<String, dynamic> chiTheoMucData = {};
    for (final muc in ChiTieuMuc.values) {
      if (muc == ChiTieuMuc.lichSu || muc == ChiTieuMuc.caiDat) continue;
      chiTheoMucData[muc.name] = _chiTheoMuc[muc]!.map((e) => e.toJson()).toList();
    }
    await prefs.setString(_keyChiTheoMuc, jsonEncode(chiTheoMucData));
    
    // Save _lichSuThang
    final Map<String, dynamic> lichSuThangData = {};
    for (final monthKey in _lichSuThang.keys) {
      lichSuThangData[monthKey] = {};
      for (final dayKey in _lichSuThang[monthKey]!.keys) {
        lichSuThangData[monthKey][dayKey] = _lichSuThang[monthKey]![dayKey]!.map((e) => {
          'muc': e.muc.name,
          'item': e.item.toJson(),
        }).toList();
      }
    }
    await prefs.setString(_keyLichSuThang, jsonEncode(lichSuThangData));
    
    // Collect expenses aggregated by category for Tile (filter by current day)
    final Map<ChiTieuMuc, int> categoryTotals = {};
    int todayTotal = 0;
    int todayIncome = 0;

    for (final muc in ChiTieuMuc.values) {
      if (muc == ChiTieuMuc.lichSu || muc == ChiTieuMuc.caiDat) continue;
      
      final items = _chiTheoMuc[muc] ?? <ChiTieuItem>[];
      int categorySum = 0;
      
      for (final item in items) {
        // Only include expenses from the current day
        if (_sameDay(item.thoiGian, _currentDay)) {
          if (muc == ChiTieuMuc.soDu) {
            todayIncome += item.soTien;
          } else {
            todayTotal += item.soTien;
            categorySum += item.soTien;
          }
        }
      }
      if (categorySum > 0 && muc != ChiTieuMuc.soDu) {
        categoryTotals[muc] = categorySum;
      }
    }
    
    // Convert to list and sort by total amount descending
    final List<Map<String, dynamic>> categoryList = categoryTotals.entries.map((e) => <String, dynamic>{
      'category': e.key.name,
      'categoryVi': _getCategoryNameVi(e.key),
      'amount': e.value,
    }).toList();
    categoryList.sort((a, b) => (b['amount'] as int).compareTo(a['amount'] as int));
    final top2 = categoryList.take(2).toList();
    
    // Save tile data with current date for day validation
    await prefs.setString('tile_today_total', todayTotal.toString());
    await prefs.setString('tile_today_income_v2', todayIncome.toString());
    await prefs.setString('tile_data_date', dinhDangNgayDayDu(_currentDay));
    await prefs.setString('app_language', _appLanguage);
    await prefs.setString('app_currency', _appCurrency);
    await prefs.setDouble('exchange_rate', _exchangeRate);
    await prefs.setString('tile_top_expenses', jsonEncode(top2));
    
    // Trigger complication update immediately
    try {
      const channel = MethodChannel('com.chiscung.quanlychitieu/complication');
      await channel.invokeMethod('updateComplication');
    } catch (_) {
      // Ignore errors - complication may not be active
    }
  }

  void _checkNewDay() {
    final now = DateTime.now();
    if (!_sameDay(now, _currentDay)) {
      if (mounted) {
        setState(() {
          _luuLichSuNgayHomQua();
          _currentDay = _asDate(now);
          _invalidateCache();
        });
        _saveData();
      }
    }
  }

  // Lưu dữ liệu của ngày cũ vào lịch sử tháng
  void _luuLichSuNgayHomQua() {
    final ngayHomQua = _currentDay;
    final monthKey = getMonthKey(ngayHomQua);
    final dayKey = dinhDangNgayDayDu(ngayHomQua);

    final List<HistoryEntry> entries = [];
    _chiTheoMuc.forEach((muc, items) {
      if (muc == ChiTieuMuc.lichSu || muc == ChiTieuMuc.caiDat) return;
      final itemsNgayHomQua = items.where((item) =>
          _sameDay(item.thoiGian, ngayHomQua)).toList();
      for (final it in itemsNgayHomQua) {
        entries.add(HistoryEntry(muc: muc, item: it));
      }
    });

    if (entries.isNotEmpty) {
      _lichSuThang.putIfAbsent(monthKey, () => {});
      _lichSuThang[monthKey]![dayKey] = entries;

      for (final muc in ChiTieuMuc.values) {
        if (muc == ChiTieuMuc.lichSu || muc == ChiTieuMuc.caiDat) continue;
        _chiTheoMuc[muc] = _chiTheoMuc[muc]!
            .where((item) => !_sameDay(item.thoiGian, ngayHomQua))
            .toList();
      }
    }
  }

  // Cập nhật lịch sử ngay khi thêm/sửa/xóa trong ngày hiện tại
  void _capNhatLichSuSauThayDoi(ChiTieuMuc muc, List<ChiTieuItem> danhSachMoi) {
    _chiTheoMuc[muc] = danhSachMoi.where((item) =>
        _sameDay(item.thoiGian, _currentDay)).toList();

    final monthKey = getMonthKey(_currentDay);
    final dayKey = dinhDangNgayDayDu(_currentDay);

    final List<HistoryEntry> allCurrentDayEntries = [];
    _chiTheoMuc.forEach((mucKey, items) {
      if (mucKey == ChiTieuMuc.lichSu || mucKey == ChiTieuMuc.caiDat) return;
      for (final it in items.where((item) => _sameDay(item.thoiGian, _currentDay))) {
        allCurrentDayEntries.add(HistoryEntry(muc: mucKey, item: it));
      }
    });

    _lichSuThang.putIfAbsent(monthKey, () => {});
    _lichSuThang[monthKey]![dayKey] = allCurrentDayEntries;
    _invalidateCache();
    setState(() {});
    _saveData();
  }

  int _tongMuc(ChiTieuMuc muc) {
    if (_cachedTongMuc.containsKey(muc)) {
      return _cachedTongMuc[muc]!;
    }
    final list = _chiTheoMuc[muc] ?? <ChiTieuItem>[];
    // Filter by current day to ensure category totals reset correctly  
    final total = list.fold(0, (a, b) => _sameDay(b.thoiGian, _currentDay) ? a + b.soTien : a);
    _cachedTongMuc[muc] = total;
    return total;
  }

  int get _tongHomNay {
    if (_cachedTongHomNay != null) {
      return _cachedTongHomNay!;
    }
    _cachedTongHomNay = _chiTheoMuc.entries.fold<int>(
      0,
      (sum, entry) {
        if (entry.key == ChiTieuMuc.soDu || entry.key == ChiTieuMuc.lichSu || entry.key == ChiTieuMuc.caiDat) return sum;
        return sum + entry.value.fold<int>(
          0,
          (a, b) => _sameDay(b.thoiGian, _currentDay) ? a + b.soTien : a,
        );
      },
    );
    return _cachedTongHomNay!;
  }

  Future<void> _moMuc(ChiTieuMuc muc) async {
    if (muc == ChiTieuMuc.soDu) {
      // Navigate to income/balance detail screen
      final danhSachThuNhap = (_chiTheoMuc[muc] ?? [])
          .where((item) => _sameDay(item.thoiGian, _currentDay))
          .toList();

      // Calculate historical expenses from _lichSuThang
      int tongChiLichSu = 0;
      for (final monthData in _lichSuThang.values) {
        for (final dayData in monthData.values) {
          for (final entry in dayData) {
            if (entry.muc != ChiTieuMuc.soDu) {
              tongChiLichSu += entry.item.soTien;
            }
          }
        }
      }

      final updated = await Navigator.push<List<ChiTieuItem>>(
        context,
        MaterialPageRoute(
          builder: (_) => SoDuScreen(
            danhSachThuNhap: danhSachThuNhap,
            tongChiHomNay: _tongHomNay,
            tongChiLichSu: tongChiLichSu,
            currentDay: _currentDay,
            onDataChanged: (newList) => _capNhatLichSuSauThayDoi(muc, newList),
          ),
        ),
      );

      if (updated != null) {
        _capNhatLichSuSauThayDoi(muc, updated);
      }
      return;
    }

    if (muc == ChiTieuMuc.lichSu) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LichSuScreen(
            lichSuThang: _lichSuThang,
            currentDay: _currentDay,
            currentData: _chiTheoMuc,
          ),
        ),
      );
      return;
    }

    if (muc == ChiTieuMuc.caiDat) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SettingsScreen(
            onLanguageChanged: () {
              // Rebuild main app and save data when language/currency changes
              if (mounted) {
                setState(() {});
                _saveData(); // Save data so Tile/Complication sync
              }
            },
          ),
        ),
      );
      return;
    }

    if (muc == ChiTieuMuc.khac) {
      final danhSachChiHienTai = (_chiTheoMuc[muc] ?? [])
          .where((item) => _sameDay(item.thoiGian, _currentDay))
          .toList();

      final updated = await Navigator.push<List<ChiTieuItem>>(
        context,
        MaterialPageRoute(
          builder: (_) => KhacTheoMucScreen(
            danhSachChiBanDau: danhSachChiHienTai,
            currentDay: _currentDay,
            onDataChanged: (newList) => _capNhatLichSuSauThayDoi(muc, newList),
          ),
        ),
      );

      if (updated != null) {
        _capNhatLichSuSauThayDoi(muc, updated);
      }
      return;
    }

    final danhSachChiHienTai = (_chiTheoMuc[muc] ?? [])
        .where((item) => _sameDay(item.thoiGian, _currentDay))
        .toList();

    final updated = await Navigator.push<List<ChiTieuItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => ChiTieuTheoMucScreen(
          muc: muc,
          danhSachChiBanDau: danhSachChiHienTai,
          currentDay: _currentDay,
          onDataChanged: (newList) => _capNhatLichSuSauThayDoi(muc, newList),
        ),
      ),
    );

    if (updated != null) {
      _capNhatLichSuSauThayDoi(muc, updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final edge =
                (constraints.maxWidth * 0.085).clamp(14.0, 30.0).toDouble();

            return Stack(
              children: [
                const _WatchBackground(),
                Column(
                  children: [
                    // Fixed clock at top - not affected by scroll
                    const SizedBox(height: 4),
                    const ClockText(showSeconds: false),
                    // Animated header that collapses on scroll (without clock)
                    ListenableBuilder(
                      listenable: _scrollAnimController,
                      builder: (context, child) {
                        final progress = _scrollAnimController.scrollProgress;
                        // Interpolate values based on scroll progress
                        final headerScale = 1.0 - (progress * 0.3);
                        final headerOpacity = 1.0 - (progress * 0.6);
                        
                        return ClipRect(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 50),
                            child: Column(
                              children: [
                                SizedBox(height: 6 * (1.0 - progress * 0.5)),
                                Opacity(
                                  opacity: headerOpacity.clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: headerScale,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: edge),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          _appLanguage == 'vi'
                                              ? 'Tổng chi tiêu ${_currentDay.day}/${_currentDay.month}:'
                                              : 'Spending ${getShortMonthName(_currentDay.month)} ${getOrdinalSuffix(_currentDay.day)}:',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.2,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 4 * (1.0 - progress * 0.5)),
                                Opacity(
                                  opacity: headerOpacity.clamp(0.0, 1.0),
                                  child: Transform.scale(
                                    scale: headerScale,
                                    child: Padding(
                                      padding: EdgeInsets.symmetric(horizontal: edge),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          formatAmountWithCurrency(_tongHomNay),
                                          style: const TextStyle(
                                            color: Color(0xFFF08080),
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Show remaining balance only if user has income
                                if (_tongMuc(ChiTieuMuc.soDu) > 0) ...[
                                  SizedBox(height: 2 * (1.0 - progress * 0.5)),
                                  Opacity(
                                    opacity: headerOpacity.clamp(0.0, 1.0),
                                    child: Transform.scale(
                                      scale: headerScale * 0.85,
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(horizontal: edge),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            () {
                                              // Current month key for filtering
                                              final currentMonthKey = getMonthKey(_currentDay);
                                              final todayDayKey = dinhDangNgayDayDu(_currentDay);
                                              
                                              // Total income from today (stored in _chiTheoMuc)
                                              int totalIncome = (_chiTheoMuc[ChiTieuMuc.soDu] ?? <ChiTieuItem>[])
                                                  .where((item) => _sameDay(item.thoiGian, _currentDay))
                                                  .fold(0, (sum, item) => sum + item.soTien);
                                              
                                              // Add historical income from current month
                                              final currentMonthData = _lichSuThang[currentMonthKey];
                                              if (currentMonthData != null) {
                                                // Since we filtered _chiTheoMuc to ONLY today, we can safely add all history
                                                // excluding today (just in case history somehow has today, though unlikely)
                                                for (final dayEntry in currentMonthData.entries) {
                                                  if (dayEntry.key == todayDayKey) continue;
                                                  for (final entry in dayEntry.value) {
                                                    if (entry.muc == ChiTieuMuc.soDu) {
                                                      totalIncome += entry.item.soTien;
                                                    }
                                                  }
                                                }
                                              }
                                              
                                              // Total expenses from today (stored in _chiTheoMuc)
                                              int totalExpenses = 0;
                                              for (final entry in _chiTheoMuc.entries) {
                                                if (entry.key == ChiTieuMuc.soDu || 
                                                    entry.key == ChiTieuMuc.lichSu || 
                                                    entry.key == ChiTieuMuc.caiDat) continue;
                                                totalExpenses += entry.value
                                                    .where((item) => _sameDay(item.thoiGian, _currentDay))
                                                    .fold(0, (sum, item) => sum + item.soTien);
                                              }
                                              // Add historical expenses from current month
                                              if (currentMonthData != null) {
                                                for (final dayEntry in currentMonthData.entries) {
                                                  if (dayEntry.key == todayDayKey) continue;
                                                  for (final entry in dayEntry.value) {
                                                    if (entry.muc != ChiTieuMuc.soDu) {
                                                      totalExpenses += entry.item.soTien;
                                                    }
                                                  }
                                                }
                                              }
                                              final remaining = totalIncome - totalExpenses;
                                              final label = _appLanguage == 'vi' ? 'Còn lại: ' : 'Left: ';
                                              // Show negative value when overspent
                                              if (remaining < 0) {
                                                return '$label-${formatAmountWithCurrency(remaining.abs())}';
                                              }
                                              return '$label${formatAmountWithCurrency(remaining)}';
                                            }(),
                                            style: TextStyle(
                                              // Green if positive/zero, red if overspent
                                              color: () {
                                                // Current month key for filtering
                                                final currentMonthKey = getMonthKey(_currentDay);
                                                final todayDayKey = dinhDangNgayDayDu(_currentDay);
                                                
                                                int totalIncome = (_chiTheoMuc[ChiTieuMuc.soDu] ?? <ChiTieuItem>[])
                                                    .where((item) => _sameDay(item.thoiGian, _currentDay))
                                                    .fold(0, (sum, item) => sum + item.soTien);
                                                // Add historical income from current month only (excluding today)
                                                final currentMonthData = _lichSuThang[currentMonthKey];
                                                if (currentMonthData != null) {
                                                  for (final dayEntry in currentMonthData.entries) {
                                                    if (dayEntry.key == todayDayKey) continue;
                                                    for (final e in dayEntry.value) {
                                                      if (e.muc == ChiTieuMuc.soDu) {
                                                        totalIncome += e.item.soTien;
                                                      }
                                                    }
                                                  }
                                                }
                                                int totalExpenses = 0;
                                                for (final entry in _chiTheoMuc.entries) {
                                                  if (entry.key == ChiTieuMuc.soDu || 
                                                      entry.key == ChiTieuMuc.lichSu || 
                                                      entry.key == ChiTieuMuc.caiDat) continue;
                                                  totalExpenses += entry.value
                                                      .where((item) => _sameDay(item.thoiGian, _currentDay))
                                                      .fold(0, (sum, item) => sum + item.soTien);
                                                }
                                                // Add historical expenses from current month only (excluding today)
                                                if (currentMonthData != null) {
                                                  for (final dayEntry in currentMonthData.entries) {
                                                    if (dayEntry.key == todayDayKey) continue;
                                                    for (final e in dayEntry.value) {
                                                      if (e.muc != ChiTieuMuc.soDu) {
                                                        totalExpenses += e.item.soTien;
                                                      }
                                                    }
                                                  }
                                                }
                                                return (totalIncome - totalExpenses) >= 0
                                                    ? const Color(0xFF4CAF93)
                                                    : const Color(0xFFE57373);
                                              }(),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                SizedBox(height: 10 * (1.0 - progress * 0.3)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    Expanded(
                      child: _ScalingGrid(
                        edge: edge,
                        itemCount: ChiTieuMuc.values.length,
                        scrollController: _scrollAnimController,
                        itemBuilder: (context, i) {
                          final muc = ChiTieuMuc.values[i];
                          // For soDu, show total income entered (not remaining balance)
                          int displayAmount;
                          if (muc == ChiTieuMuc.lichSu || muc == ChiTieuMuc.caiDat) {
                            displayAmount = 0;
                          } else if (muc == ChiTieuMuc.soDu) {
                            // Show total income entered
                            displayAmount = (_chiTheoMuc[ChiTieuMuc.soDu] ?? <ChiTieuItem>[])
                                .fold(0, (sum, item) => sum + item.soTien);
                          } else {
                            displayAmount = _tongMuc(muc);
                          }

                          return _CategoryButton(
                            icon: muc.icon,
                            tongTien: displayAmount,
                            isBalance: muc == ChiTieuMuc.soDu,
                            onTap: () => _moMuc(muc),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// =================== SMOOTH SCROLL CONTROLLER ===================

class SmoothScrollController extends ChangeNotifier {
  double _scrollProgress = 0.0;
  double get scrollProgress => _scrollProgress;
  
  void updateProgress(double progress) {
    _scrollProgress = progress.clamp(0.0, 1.0);
    notifyListeners();
  }
}

// =================== SCALING GRID ===================

class _ScalingGrid extends StatefulWidget {
  final double edge;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final SmoothScrollController? scrollController;

  const _ScalingGrid({
    required this.edge,
    required this.itemCount,
    required this.itemBuilder,
    this.scrollController,
  });

  @override
  State<_ScalingGrid> createState() => _ScalingGridState();
}

class _ScalingGridState extends State<_ScalingGrid> {
  final ScrollController _controller = ScrollController();

  static const int _crossAxisCount = 2;
  static const double _mainSpacing = 10;
  static const double _crossSpacing = 10;
  static const double _childAspectRatio = 1.3;
  static const double _maxScrollThreshold = 60.0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (widget.scrollController != null) {
      final offset = _controller.offset;
      final progress = (offset / _maxScrollThreshold).clamp(0.0, 1.0);
      widget.scrollController!.updateProgress(progress);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GridView.builder(
          controller: _controller,
          padding: EdgeInsets.fromLTRB(widget.edge, 0, widget.edge, widget.edge),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _crossAxisCount,
            mainAxisSpacing: _mainSpacing,
            crossAxisSpacing: _crossSpacing,
            childAspectRatio: _childAspectRatio,
          ),
          itemCount: widget.itemCount,
          itemBuilder: (context, index) {
            return RepaintBoundary(
              child: widget.itemBuilder(context, index),
            );
          },
        );
      },
    );
  }
}

// =================== CATEGORY BUTTON ===================

class _CategoryButton extends StatelessWidget {
  final IconData icon;
  final int tongTien;
  final VoidCallback onTap;
  final bool isBalance;

  // Pre-cached decoration for performance
  static final BorderRadius _borderRadius = BorderRadius.circular(18);
  static const BoxDecoration _decoration = BoxDecoration(
    color: Color(0xFF1B1B1B),
  );

  const _CategoryButton({
    required this.icon,
    required this.tongTien,
    required this.onTap,
    this.isBalance = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool coTien = tongTien > 0;

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: _decoration.copyWith(borderRadius: _borderRadius),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: const Color(0xFFFFFFFF),
              size: coTien ? 24 : 28,
            ),
            if (coTien) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  formatAmountWithCurrency(tongTien),
                  style: TextStyle(
                    // Green for balance, coral red for expenses
                    color: isBalance ? const Color(0xFF4CAF93) : const Color(0xFFF08080),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =================== INCOME/BALANCE DETAIL SCREEN ===================

class SoDuScreen extends StatefulWidget {
  final List<ChiTieuItem> danhSachThuNhap;
  final int tongChiHomNay;
  final int tongChiLichSu; // Historical expenses
  final DateTime currentDay;
  final Function(List<ChiTieuItem>)? onDataChanged;

  const SoDuScreen({
    super.key,
    required this.danhSachThuNhap,
    required this.tongChiHomNay,
    required this.tongChiLichSu,
    required this.currentDay,
    this.onDataChanged,
  });

  @override
  State<SoDuScreen> createState() => _SoDuScreenState();
}

class _SoDuScreenState extends State<SoDuScreen> {
  late List<ChiTieuItem> danhSachThuNhap;
  bool dangChonXoa = false;

  int get tongThuNhap => danhSachThuNhap.fold(0, (a, b) => a + b.soTien);

  @override
  void initState() {
    super.initState();
    danhSachThuNhap = List<ChiTieuItem>.from(widget.danhSachThuNhap);
  }

  Future<void> themThuNhap() async {
    final soTien = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const NhapSoTienScreen()),
    );

    if (soTien != null && soTien > 0) {
      setState(() {
        danhSachThuNhap.add(
          ChiTieuItem(soTien: soTien, thoiGian: DateTime.now()),
        );
        widget.onDataChanged?.call(danhSachThuNhap);
      });
    }
  }

  Future<void> chinhSuaThuNhap(int index) async {
    if (dangChonXoa) return;
    final soTienMoi = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => NhapSoTienScreen(
          soTienBanDau: danhSachThuNhap[index].soTien,
        ),
      ),
    );

    if (soTienMoi != null && soTienMoi > 0) {
      setState(() {
        danhSachThuNhap[index] = danhSachThuNhap[index].copyWith(
          soTien: soTienMoi,
          thoiGian: DateTime.now(),
        );
        widget.onDataChanged?.call(danhSachThuNhap);
      });
    }
  }

  void batDauChonXoa() {
    if (danhSachThuNhap.isEmpty) return;
    setState(() {
      dangChonXoa = true;
    });
  }

  void huyChonXoa() {
    setState(() {
      dangChonXoa = false;
    });
  }

  Future<void> xacNhanXoa(int index) async {
    final soTien = danhSachThuNhap[index].soTien;
    final dongY = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => XacNhanXoaScreen(soTien: soTien, isIncome: true),
      ),
    );

    if (dongY == true) {
      setState(() {
        danhSachThuNhap.removeAt(index);
        if (danhSachThuNhap.isEmpty) {
          dangChonXoa = false;
        }
        widget.onDataChanged?.call(danhSachThuNhap);
      });
    }
  }

  Widget _circleBtn(IconData icon, Color bg, {Color colorIcon = Colors.white}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: colorIcon, size: 22),
    );
  }

  List<_ListRow> _nhomTheoNgay(List<ChiTieuItem> items) {
    final sorted = List<ChiTieuItem>.from(items);
    sorted.sort((a, b) => b.thoiGian.compareTo(a.thoiGian));

    final List<_ListRow> rows = [];
    final Map<String, List<ChiTieuItem>> grouped = {};

    for (var item in sorted) {
      final dateKey = dinhDangNgayDayDu(item.thoiGian);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(item);
    }

    final sortedDateKeys = grouped.keys.toList()
      ..sort((a, b) {
        final pa = a.split('/');
        final pb = b.split('/');
        final da = DateTime(int.parse(pa[2]), int.parse(pa[1]), int.parse(pa[0]));
        final db = DateTime(int.parse(pb[2]), int.parse(pb[1]), int.parse(pb[0]));
        return db.compareTo(da);
      });

    for (var dateKey in sortedDateKeys) {
      final dailyList = grouped[dateKey]!;
      final dailySum = dailyList.fold(0, (sum, item) => sum + item.soTien);
      rows.add(_ListRow.header(dateKey, dailySum));
      rows.addAll(dailyList.map((e) => _ListRow.item(e)));
    }

    return rows;
  }

  @override
  Widget build(BuildContext context) {
    // Include historical expenses in remaining calculation
    final remaining = tongThuNhap - widget.tongChiHomNay - widget.tongChiLichSu;
    final isOverspent = remaining < 0;

    final rows = _nhomTheoNgay(danhSachThuNhap);

    return WillPopScope(
      onWillPop: () async {
        if (dangChonXoa) {
          huyChonXoa();
          return false;
        }
        widget.onDataChanged?.call(danhSachThuNhap);
        Navigator.pop(context, danhSachThuNhap);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final edge = (constraints.maxWidth * 0.10).clamp(16.0, 36.0).toDouble();
              final dateMaxWidth = (constraints.maxWidth * 0.40).clamp(72.0, 120.0).toDouble();

              return Stack(
                children: [
                  const _WatchBackground(),
                  Column(
                    children: [
                      const SizedBox(height: 4),
                      const ClockText(),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            _appLanguage == 'vi' ? 'Số dư' : 'Balance',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      // Total Income Display
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: edge),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatAmountWithCurrency(tongThuNhap),
                            style: const TextStyle(
                              color: Color(0xFF4CAF93),
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Income list grouped by date
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(horizontal: edge, vertical: 4),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final row = rows[index];

                            if (row.isHeader) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                                child: Row(
                                  children: [
                                    Text(
                                      row.dateHeader!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          formatAmountWithCurrency(row.dailyTotal!),
                                          style: const TextStyle(
                                            color: Color(0xFF4CAF93),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final item = row.item!;
                            final timeText = dinhDangGio(item.thoiGian);
                            final moneyText = formatAmountWithCurrency(item.soTien);
                            final originalIndex = danhSachThuNhap.indexOf(item);

                            return GestureDetector(
                              onTap: () {
                                if (dangChonXoa) {
                                  xacNhanXoa(originalIndex);
                                } else {
                                  chinhSuaThuNhap(originalIndex);
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: dangChonXoa
                                      ? Colors.red.withOpacity(0.15)
                                      : Colors.white12,
                                  borderRadius: BorderRadius.circular(10),
                                  border: dangChonXoa
                                      ? Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1)
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    ConstrainedBox(
                                      constraints: BoxConstraints(maxWidth: dateMaxWidth),
                                      child: Text(
                                        timeText,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            moneyText,
                                            style: const TextStyle(
                                              color: Color(0xFF4CAF93),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(
                                      dangChonXoa ? Icons.remove_circle_outline : Icons.edit,
                                      color: dangChonXoa ? Colors.redAccent : Colors.white30,
                                      size: 14,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // Action buttons
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16, top: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (dangChonXoa) {
                                  huyChonXoa();
                                } else {
                                  batDauChonXoa();
                                }
                              },
                              child: _circleBtn(
                                dangChonXoa ? Icons.close : Icons.delete_outline,
                                dangChonXoa
                                    ? const Color(0xFF555555)
                                    : (danhSachThuNhap.isEmpty
                                        ? const Color(0xFF333333)
                                        : const Color(0xFFE57373)),
                                colorIcon: danhSachThuNhap.isEmpty && !dangChonXoa
                                    ? Colors.white38
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 24),
                            GestureDetector(
                              onTap: dangChonXoa ? null : themThuNhap,
                              child: _circleBtn(
                                Icons.add,
                                dangChonXoa
                                    ? const Color(0xFF333333)
                                    : const Color(0xFF4CAF93),
                                colorIcon: dangChonXoa ? Colors.white38 : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: edge,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white70,
                        size: 16,
                      ),
                      onPressed: () {
                        if (dangChonXoa) {
                          huyChonXoa();
                        } else {
                          widget.onDataChanged?.call(danhSachThuNhap);
                          Navigator.pop(context, danhSachThuNhap);
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// =================== LỊCH SỬ CHI TIÊU SCREEN ===================

class LichSuScreen extends StatefulWidget {
  final Map<String, Map<String, List<HistoryEntry>>> lichSuThang;
  final DateTime currentDay;
  final Map<ChiTieuMuc, List<ChiTieuItem>> currentData;

  const LichSuScreen({
    super.key,
    required this.lichSuThang,
    required this.currentDay,
    required this.currentData,
  });

  @override
  State<LichSuScreen> createState() => _LichSuScreenState();
}

class _LichSuScreenState extends State<LichSuScreen> {
  final Set<String> _expandedDayKeys = {};

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final edge = (MediaQuery.of(context).size.width * 0.10).clamp(16.0, 36.0);

    final Map<String, Map<String, List<HistoryEntry>>> combined = {
      for (final e in widget.lichSuThang.entries)
        e.key: {
          for (final d in e.value.entries) d.key: List<HistoryEntry>.from(d.value)
        }
    };

    final monthKeyNow = getMonthKey(widget.currentDay);
    final dayKeyNow = dinhDangNgayDayDu(widget.currentDay);
    final List<HistoryEntry> currentDayEntries = [];
    widget.currentData.forEach((muc, items) {
      if (muc == ChiTieuMuc.lichSu) return;
      for (final it in items.where((item) => _sameDay(item.thoiGian, widget.currentDay))) {
        currentDayEntries.add(HistoryEntry(muc: muc, item: it));
      }
    });
    currentDayEntries.sort((a, b) => b.item.soTien.compareTo(a.item.soTien));
    if (currentDayEntries.isNotEmpty) {
      combined.putIfAbsent(monthKeyNow, () => {});
      combined[monthKeyNow]![dayKeyNow] = currentDayEntries;
    }

    final sortedMonths = combined.keys.toList()
      ..sort((a, b) {
        final pa = a.split('/');
        final pb = b.split('/');
        final da = DateTime(int.parse(pa[1]), int.parse(pa[0]));
        final db = DateTime(int.parse(pb[1]), int.parse(pb[0]));
        return db.compareTo(da);
      });

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            const _WatchBackground(),
            Column(
              children: [
                const SizedBox(height: 4),
                const ClockText(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.history_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      _appLanguage == 'vi' ? 'Lịch sử' : 'History',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: sortedMonths.isEmpty
                      ? Center(
                          child: Text(
                            _appLanguage == 'vi' ? 'Chưa có dữ liệu' : 'No data',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(edge, 0, edge, 20),
                          itemCount: sortedMonths.length,
                          itemBuilder: (context, monthIndex) {
                            final monthKey = sortedMonths[monthIndex];
                            final daysData = combined[monthKey]!;

                            // Total expenses for month (exclude income/soDu)
                            final totalMonth = daysData.values
                                .expand((lst) => lst)
                                .where((e) => e.muc != ChiTieuMuc.soDu)
                                .fold(0, (s, e) => s + e.item.soTien);
                            
                            // Total income for month
                            final incomeMonth = daysData.values
                                .expand((lst) => lst)
                                .where((e) => e.muc == ChiTieuMuc.soDu)
                                .fold(0, (s, e) => s + e.item.soTien);
                            final monthlyRemaining = incomeMonth - totalMonth;
                            final hasAnyIncome = incomeMonth > 0;

                            final sortedDays = daysData.keys.toList()
                              ..sort((a, b) {
                                final pa = a.split('/');
                                final pb = b.split('/');
                                final da = DateTime(int.parse(pa[2]), int.parse(pa[1]), int.parse(pa[0]));
                                final db = DateTime(int.parse(pb[2]), int.parse(pb[1]), int.parse(pb[0]));
                                return db.compareTo(da);
                              });

                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white12,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            () {
                                            final parts = monthKey.split('/');
                                            final month = int.parse(parts[0]);
                                            final year = parts[1];
                                            if (_appLanguage == 'en') {
                                              return '${getMonthName(month)} $year';
                                            }
                                            return 'Th.$monthKey';
                                          }(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                        Flexible(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(
                                                  formatAmountWithCurrency(totalMonth),
                                                  style: const TextStyle(
                                                    color: Color(0xFFF08080),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                              if (hasAnyIncome)
                                                FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  child: Text(
                                                    monthlyRemaining >= 0
                                                        ? formatAmountWithCurrency(monthlyRemaining)
                                                        : '-${formatAmountWithCurrency(monthlyRemaining.abs())}',
                                                    style: TextStyle(
                                                      color: monthlyRemaining >= 0
                                                          ? const Color(0xFF4CAF93)
                                                          : const Color(0xFFE57373),
                                                      fontWeight: FontWeight.w600,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],                                    
                                    ),
                                  ),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: sortedDays.length,
                                    itemBuilder: (context, dayIndex) {
                                      final dayKey = sortedDays[dayIndex];
                                      final itemsOnDay = daysData[dayKey]!;
                                      final dayToggleKey = '$monthKey|$dayKey';
                                      final expanded = _expandedDayKeys.contains(dayToggleKey);

                                      final Map<ChiTieuMuc, List<HistoryEntry>> groupByCategory = {};
                                      for (final entry in itemsOnDay) {
                                        groupByCategory.putIfAbsent(entry.muc, () => []);
                                        groupByCategory[entry.muc]!.add(entry);
                                      }

                                      // Calculate daily total (exclude income/soDu)
                                      final dayTotal = itemsOnDay
                                          .where((e) => e.muc != ChiTieuMuc.soDu)
                                          .fold(0, (sum, e) => sum + e.item.soTien);
                                      
                                      // Calculate daily income and remaining
                                      final dayIncome = itemsOnDay
                                          .where((e) => e.muc == ChiTieuMuc.soDu)
                                          .fold(0, (sum, e) => sum + e.item.soTien);
                                      final dayRemaining = dayIncome - dayTotal;

                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                setState(() {
                                                  if (expanded) {
                                                    _expandedDayKeys.remove(dayToggleKey);
                                                  } else {
                                                    _expandedDayKeys.add(dayToggleKey);
                                                  }
                                                });
                                              },
                                              borderRadius: BorderRadius.circular(8),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 4),
                                                child: Row(
                                                  children: [
                                                    Text(
                                                      () {
                                                        final day = int.parse(dayKey.split('/')[0]);
                                                        if (_appLanguage == 'en') {
                                                          return getOrdinalSuffix(day);
                                                        }
                                                        return 'Ngày $day';
                                                      }(),
                                                      style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.end,
                                                        children: [
                                                          // Expense total in red
                                                          FittedBox(
                                                            fit: BoxFit.scaleDown,
                                                            child: Text(
                                                              formatAmountWithCurrency(dayTotal),
                                                              style: const TextStyle(
                                                                color: Color(0xFFF08080),
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                          ),
                                                          // Remaining (if there was income)
                                                          if (dayIncome > 0)
                                                            FittedBox(
                                                              fit: BoxFit.scaleDown,
                                                              child: Text(
                                                                dayRemaining >= 0
                                                                    ? formatAmountWithCurrency(dayRemaining)
                                                                    : '-${formatAmountWithCurrency(dayRemaining.abs())}',
                                                                style: TextStyle(
                                                                  color: dayRemaining >= 0
                                                                      ? const Color(0xFF4CAF93)
                                                                      : const Color(0xFFE57373),
                                                                  fontSize: 9,
                                                                  fontWeight: FontWeight.w500,
                                                                ),
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Icon(
                                                      expanded
                                                          ? Icons.keyboard_arrow_up_rounded
                                                          : Icons.keyboard_arrow_down_rounded,
                                                      color: Colors.white54,
                                                      size: 16,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            if (expanded) ...[
                                              const SizedBox(height: 4),
                                              // Sort categories so income (soDu) appears first
                                              ...(groupByCategory.entries.toList()
                                                ..sort((a, b) {
                                                  if (a.key == ChiTieuMuc.soDu) return -1;
                                                  if (b.key == ChiTieuMuc.soDu) return 1;
                                                  return 0;
                                                })).map((catEntry) {
                                                final muc = catEntry.key;
                                                final entries = List<HistoryEntry>.from(catEntry.value)
                                                  ..sort((a, b) => b.item.soTien.compareTo(a.item.soTien));
                                                final totalCat = entries.fold(0, (s, e) => s + e.item.soTien);

                                                return Padding(
                                                  padding: const EdgeInsets.only(bottom: 6),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Icon(muc.icon, size: 16, color: Colors.white70),
                                                          const SizedBox(width: 6),
                                                          Expanded(
                                                            child: FittedBox(
                                                              fit: BoxFit.scaleDown,
                                                              alignment: Alignment.centerLeft,
                                                                child: Text(
                                                                  formatAmountWithCurrency(totalCat),
                                                                  style: TextStyle(
                                                                    // Green for income, white for expenses
                                                                    color: muc == ChiTieuMuc.soDu
                                                                        ? const Color(0xFF4CAF93)
                                                                        : Colors.white,
                                                                    fontSize: 12,
                                                                    fontWeight: FontWeight.w600,
                                                                  ),
                                                                ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      ...entries.map((entry) {
                                                        final timeText = dinhDangGio(entry.item.thoiGian);
                                                        final moneyText = formatAmountWithCurrency(entry.item.soTien);
                                                        final tenChiTieu = entry.item.tenChiTieu;
                                                        final isKhac = entry.muc == ChiTieuMuc.khac && tenChiTieu != null;
                                                        final isIncome = entry.muc == ChiTieuMuc.soDu;
                                                        // Income color is green, expenses are white
                                                        final amountColor = isIncome ? const Color(0xFF4CAF93) : Colors.white;
                                                        
                                                        return Padding(
                                                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
                                                          child: isKhac
                                                              ? Column(
                                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                                  children: [
                                                                    Text(
                                                                      tenChiTieu,
                                                                      style: const TextStyle(
                                                                        color: Colors.white70,
                                                                        fontSize: 11,
                                                                        fontWeight: FontWeight.w500,
                                                                      ),
                                                                      maxLines: 1,
                                                                      overflow: TextOverflow.ellipsis,
                                                                    ),
                                                                    Row(
                                                                      children: [
                                                                        Text(
                                                                          timeText,
                                                                          style: const TextStyle(
                                                                            color: Colors.white54,
                                                                            fontSize: 10,
                                                                          ),
                                                                        ),
                                                                        const SizedBox(width: 8),
                                                                        Expanded(
                                                                          child: FittedBox(
                                                                            fit: BoxFit.scaleDown,
                                                                            alignment: Alignment.centerRight,
                                                                            child: Text(
                                                                              moneyText,
                                                                              style: TextStyle(
                                                                                color: amountColor,
                                                                                fontSize: 12,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ],
                                                                )
                                                              : Row(
                                                                  children: [
                                                                    Text(
                                                                      timeText,
                                                                      style: const TextStyle(
                                                                        color: Colors.white54,
                                                                        fontSize: 12,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(width: 8),
                                                                    Expanded(
                                                                      child: FittedBox(
                                                                        fit: BoxFit.scaleDown,
                                                                        alignment: Alignment.centerRight,
                                                                        child: Text(
                                                                          moneyText,
                                                                          style: TextStyle(
                                                                            color: amountColor,
                                                                            fontSize: 12,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                        );
                                                      }),
                                                    ],
                                                  ),
                                                );
                                              }),
                                              const SizedBox(height: 4),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
            Positioned(
              top: 12,
              left: edge,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =================== CATEGORY DETAIL ===================

class ChiTieuTheoMucScreen extends StatefulWidget {
  final ChiTieuMuc muc;
  final List<ChiTieuItem> danhSachChiBanDau;
  final DateTime currentDay;
  final Function(List<ChiTieuItem>)? onDataChanged;

  const ChiTieuTheoMucScreen({
    super.key,
    required this.muc,
    required this.danhSachChiBanDau,
    required this.currentDay,
    this.onDataChanged,
  });

  @override
  State<ChiTieuTheoMucScreen> createState() => _ChiTieuTheoMucScreenState();
}

class _ListRow {
  final String? dateHeader;
  final int? dailyTotal;
  final ChiTieuItem? item;

  _ListRow.header(this.dateHeader, this.dailyTotal) : item = null;
  _ListRow.item(this.item) : dateHeader = null, dailyTotal = null;

  bool get isHeader => dateHeader != null;
}

class _ChiTieuTheoMucScreenState extends State<ChiTieuTheoMucScreen> {
  late List<ChiTieuItem> danhSachChi;
  bool dangChonXoa = false;

  int get tongChi => danhSachChi.fold(0, (a, b) => a + b.soTien);

  @override
  void initState() {
    super.initState();
    danhSachChi = List<ChiTieuItem>.from(widget.danhSachChiBanDau);
  }

  List<_ListRow> _nhomTheoNgay(List<ChiTieuItem> items) {
    final sorted = List<ChiTieuItem>.from(items);
    sorted.sort((a, b) => b.thoiGian.compareTo(a.thoiGian));

    final List<_ListRow> rows = [];
    final Map<String, List<ChiTieuItem>> grouped = {};

    for (var item in sorted) {
      final dateKey = dinhDangNgayDayDu(item.thoiGian);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(item);
    }

    final sortedDateKeys = grouped.keys.toList()
      ..sort((a, b) {
        final pa = a.split('/');
        final pb = b.split('/');
        final da = DateTime(int.parse(pa[2]), int.parse(pa[1]), int.parse(pa[0]));
        final db = DateTime(int.parse(pb[2]), int.parse(pb[1]), int.parse(pb[0]));
        return db.compareTo(da);
      });

    for (var dateKey in sortedDateKeys) {
      final dailyList = grouped[dateKey]!;
      final dailySum = dailyList.fold(0, (sum, item) => sum + item.soTien);
      rows.add(_ListRow.header(dateKey, dailySum));
      rows.addAll(dailyList.map((e) => _ListRow.item(e)));
    }

    return rows;
  }

  Future<void> themChiTieu() async {
    final soTien = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => const NhapSoTienScreen()),
    );

    if (soTien != null && soTien > 0) {
      setState(() {
        danhSachChi.add(
          ChiTieuItem(soTien: soTien, thoiGian: DateTime.now()),
        );
        widget.onDataChanged?.call(danhSachChi);
      });
    }
  }

  Future<void> chinhSuaChiTieu(int index) async {
    if (dangChonXoa) return;
    final soTienMoi = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => NhapSoTienScreen(
          soTienBanDau: danhSachChi[index].soTien,
        ),
      ),
    );

    if (soTienMoi != null && soTienMoi > 0) {
      setState(() {
        danhSachChi[index] = danhSachChi[index].copyWith(
          soTien: soTienMoi,
          thoiGian: DateTime.now(),
        );
        widget.onDataChanged?.call(danhSachChi);
      });
    }
  }

  void batDauChonXoa() {
    if (danhSachChi.isEmpty) return;
    setState(() {
      dangChonXoa = true;
    });
  }

  void huyChonXoa() {
    setState(() {
      dangChonXoa = false;
    });
  }

  Future<void> xacNhanXoa(int index) async {
    final soTien = danhSachChi[index].soTien;
    final dongY = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => XacNhanXoaScreen(soTien: soTien),
      ),
    );

    if (dongY == true) {
      setState(() {
        danhSachChi.removeAt(index);
        if (danhSachChi.isEmpty) {
          dangChonXoa = false;
        }
        widget.onDataChanged?.call(danhSachChi);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _nhomTheoNgay(danhSachChi);

    return WillPopScope(
      onWillPop: () async {
        if (dangChonXoa) {
          huyChonXoa();
          return false;
        }
        widget.onDataChanged?.call(danhSachChi);
        Navigator.pop(context, danhSachChi);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final edge =
                  (constraints.maxWidth * 0.10).clamp(16.0, 36.0).toDouble();

              final dateMaxWidth =
                  (constraints.maxWidth * 0.40).clamp(72.0, 120.0).toDouble();

              return Stack(
                children: [
                  const _WatchBackground(),
                  Column(
                    children: [
                      const SizedBox(height: 4),
                      const ClockText(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(widget.muc.icon, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            widget.muc.ten,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: edge),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatAmountWithCurrency(tongChi),
                            style: const TextStyle(
                              color: Color(0xFFF08080),
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(
                              horizontal: edge, vertical: 6),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final row = rows[index];

                            if (row.isHeader) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 2),
                                child: Row(
                                  children: [
                                    Text(
                                      row.dateHeader!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          formatAmountWithCurrency(row.dailyTotal!),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final item = row.item!;
                            final timeText = dinhDangGio(item.thoiGian);
                            final moneyText = formatAmountWithCurrency(item.soTien);
                            final originalIndex = danhSachChi.indexOf(item);

                            return GestureDetector(
                              onTap: () {
                                if (dangChonXoa) {
                                  xacNhanXoa(originalIndex);
                                } else {
                                  chinhSuaChiTieu(originalIndex);
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: dangChonXoa
                                      ? Colors.red.withOpacity(0.15)
                                      : Colors.white12,
                                  borderRadius: BorderRadius.circular(12),
                                  border: dangChonXoa
                                      ? Border.all(
                                          color: Colors.redAccent
                                              .withOpacity(0.5),
                                          width: 1)
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: dateMaxWidth),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          timeText,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            moneyText,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      dangChonXoa
                                          ? Icons.remove_circle_outline
                                          : Icons.edit,
                                      color: dangChonXoa
                                          ? Colors.redAccent
                                          : Colors.white30,
                                      size: 14,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16, top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (dangChonXoa) {
                                  huyChonXoa();
                                } else {
                                  batDauChonXoa();
                                }
                              },
                              child: _circleBtn(
                                dangChonXoa
                                    ? Icons.close
                                    : Icons.delete_outline,
                                dangChonXoa
                                    ? const Color(0xFF555555)
                                    : (danhSachChi.isEmpty
                                        ? const Color(0xFF333333)
                                        : const Color(0xFFE57373)),
                                colorIcon: danhSachChi.isEmpty && !dangChonXoa
                                    ? Colors.white38
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 24),
                            GestureDetector(
                              onTap: dangChonXoa ? null : themChiTieu,
                              child: _circleBtn(
                                Icons.add,
                                dangChonXoa
                                    ? const Color(0xFF333333)
                                    : const Color(0xFF4CAF93),
                                colorIcon:
                                    dangChonXoa ? Colors.white38 : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: edge,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white70,
                        size: 16,
                      ),
                      onPressed: () {
                        if (dangChonXoa) {
                          huyChonXoa();
                        } else {
                          widget.onDataChanged?.call(danhSachChi);
                          Navigator.pop(context, danhSachChi);
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color bg, {Color colorIcon = Colors.white}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: colorIcon, size: 22),
    );
  }
}

// =================== SCREEN XÁC NHẬN XÓA ===================

class XacNhanXoaScreen extends StatelessWidget {
  final int soTien;
  final bool isIncome;

  const XacNhanXoaScreen({super.key, required this.soTien, this.isIncome = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            const _WatchBackground(),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isIncome
                          ? (_appLanguage == 'vi' ? 'Bạn có muốn xóa khoản thu' : 'Delete income')
                          : (_appLanguage == 'vi' ? 'Bạn có muốn xóa khoản chi' : 'Delete expense'),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 0),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatAmountWithCurrency(soTien),
                        style: TextStyle(
                          color: isIncome ? const Color(0xFF4CAF93) : const Color(0xFFF08080),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 0),
                    Text(
                      _appLanguage == 'vi' ? 'này không?' : '',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context, true),
                          child: _circleBtn(
                              Icons.delete_outline, const Color(0xFFE57373)),
                        ),
                        const SizedBox(width: 32),
                        GestureDetector(
                          onTap: () => Navigator.pop(context, false),
                          child:
                              _circleBtn(Icons.close, const Color(0xFF666666)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

// =================== INPUT SCREEN ===================

class NhapSoTienScreen extends StatefulWidget {
  final int? soTienBanDau;

  const NhapSoTienScreen({super.key, this.soTienBanDau});

  @override
  State<NhapSoTienScreen> createState() => _NhapSoTienScreenState();
}

class _NhapSoTienScreenState extends State<NhapSoTienScreen> {
  late final TextEditingController controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();

    String initText = '';
    if (widget.soTienBanDau != null) {
      if (_appCurrency == '\$') {
        // Convert VND to USD for display
        final usdAmount = widget.soTienBanDau! * _exchangeRate;
        initText = usdAmount.toStringAsFixed(2);
      } else {
        initText = widget.soTienBanDau.toString();
      }
    }
    controller = TextEditingController(text: initText);

    controller.addListener(() {
      final len = controller.text.length;
      final sel = controller.selection;
      if (sel.start > len || sel.end > len) {
        controller.selection = TextSelection.collapsed(offset: len);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();

      if (widget.soTienBanDau != null && initText.isNotEmpty) {
        controller.selection =
            TextSelection(baseOffset: 0, extentOffset: initText.length);
      } else {
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    controller.dispose();
    super.dispose();
  }

  int? _layGiaTriSo() {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    try {
      if (_appCurrency == '\$') {
        // USD mode: parse as double (allowing decimals) and convert to VND
        final usdAmount = double.parse(text.replaceAll(',', '.'));
        if (_exchangeRate > 0) {
          // Convert USD back to VND for storage - no rounding
          return (usdAmount / _exchangeRate).toInt();
        }
        return (usdAmount * 25000).toInt(); // Fallback rate
      }
      // VND mode: parse as integer directly
      return int.parse(text);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.soTienBanDau != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            const _WatchBackground(),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isEdit 
                        ? (_appLanguage == 'vi' ? 'Sửa số tiền' : 'Edit amount')
                        : (_appLanguage == 'vi' ? 'Nhập số tiền' : 'Enter amount'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: TextField(
                      focusNode: _focusNode,
                      controller: controller,
                      keyboardType: _appCurrency == '\$' 
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.number,
                      inputFormatters: _appCurrency == '\$'
                          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
                          : [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: Color(0xFFF08080),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '0',
                        hintStyle: const TextStyle(color: Colors.white24),
                        suffixText: _appCurrency == '\$' ? '\$' : 'đ',
                        suffixStyle: const TextStyle(
                          color: Color(0xFFF08080),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFF08080)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: _circleBtn(Icons.close, const Color(0xFF555555)),
                      ),
                      const SizedBox(width: 32),
                      GestureDetector(
                        onTap: () => Navigator.pop(context, _layGiaTriSo()),
                        child: _circleBtn(Icons.check, const Color(0xFF4CAF93)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

// =================== KHÁC DETAIL SCREEN ===================

class KhacTheoMucScreen extends StatefulWidget {
  final List<ChiTieuItem> danhSachChiBanDau;
  final DateTime currentDay;
  final Function(List<ChiTieuItem>)? onDataChanged;

  const KhacTheoMucScreen({
    super.key,
    required this.danhSachChiBanDau,
    required this.currentDay,
    this.onDataChanged,
  });

  @override
  State<KhacTheoMucScreen> createState() => _KhacTheoMucScreenState();
}

class _KhacTheoMucScreenState extends State<KhacTheoMucScreen> {
  late List<ChiTieuItem> danhSachChi;
  bool dangChonXoa = false;

  int get tongChi => danhSachChi.fold(0, (a, b) => a + b.soTien);

  @override
  void initState() {
    super.initState();
    danhSachChi = List<ChiTieuItem>.from(widget.danhSachChiBanDau);
  }

  Future<void> themChiTieu() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const NhapChiTieuKhacScreen()),
    );

    if (result != null) {
      setState(() {
        danhSachChi.add(
          ChiTieuItem(
            soTien: result['soTien'] as int,
            thoiGian: DateTime.now(),
            tenChiTieu: result['tenChiTieu'] as String,
          ),
        );
        widget.onDataChanged?.call(danhSachChi);
      });
    }
  }

  Future<void> chinhSuaChiTieu(int index) async {
    if (dangChonXoa) return;
    final item = danhSachChi[index];
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => NhapChiTieuKhacScreen(
          tenBanDau: item.tenChiTieu,
          soTienBanDau: item.soTien,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        danhSachChi[index] = ChiTieuItem(
          soTien: result['soTien'] as int,
          thoiGian: DateTime.now(),
          tenChiTieu: result['tenChiTieu'] as String,
        );
        widget.onDataChanged?.call(danhSachChi);
      });
    }
  }

  void batDauChonXoa() {
    if (danhSachChi.isEmpty) return;
    setState(() {
      dangChonXoa = true;
    });
  }

  void huyChonXoa() {
    setState(() {
      dangChonXoa = false;
    });
  }

  Future<void> xacNhanXoa(int index) async {
    final item = danhSachChi[index];
    final dongY = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => XacNhanXoaKhacScreen(
          soTien: item.soTien,
          tenChiTieu: item.tenChiTieu ?? 'Khoản chi khác',
        ),
      ),
    );

    if (dongY == true) {
      setState(() {
        danhSachChi.removeAt(index);
        if (danhSachChi.isEmpty) {
          dangChonXoa = false;
        }
        widget.onDataChanged?.call(danhSachChi);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (dangChonXoa) {
          huyChonXoa();
          return false;
        }
        widget.onDataChanged?.call(danhSachChi);
        Navigator.pop(context, danhSachChi);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final edge =
                  (constraints.maxWidth * 0.10).clamp(16.0, 36.0).toDouble();

              return Stack(
                children: [
                  const _WatchBackground(),
                  Column(
                    children: [
                      const SizedBox(height: 4),
                      const ClockText(),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (dangChonXoa) {
                                huyChonXoa();
                              } else {
                                widget.onDataChanged?.call(danhSachChi);
                                Navigator.pop(context, danhSachChi);
                              }
                            },
                            child: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white70,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.money_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            _appLanguage == 'vi' ? 'Khoản chi khác' : 'Other expenses',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: edge),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            formatAmountWithCurrency(tongChi),
                            style: const TextStyle(
                              color: Color(0xFFF08080),
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.symmetric(
                              horizontal: edge, vertical: 6),
                          itemCount: danhSachChi.length,
                          itemBuilder: (context, index) {
                            final item = danhSachChi[index];
                            final timeText = dinhDangGio(item.thoiGian);
                            final moneyText = formatAmountWithCurrency(item.soTien);
                            final tenChiTieu = item.tenChiTieu ?? 'Khoản chi khác';

                            return GestureDetector(
                              onTap: () {
                                if (dangChonXoa) {
                                  xacNhanXoa(index);
                                } else {
                                  chinhSuaChiTieu(index);
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: dangChonXoa
                                      ? Colors.red.withOpacity(0.15)
                                      : Colors.white12,
                                  borderRadius: BorderRadius.circular(12),
                                  border: dangChonXoa
                                      ? Border.all(
                                          color: Colors.redAccent
                                              .withOpacity(0.5),
                                          width: 1)
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            tenChiTieu,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (dangChonXoa)
                                          const Icon(
                                            Icons.remove_circle_outline,
                                            color: Colors.redAccent,
                                            size: 14,
                                          )
                                        else
                                          const Icon(
                                            Icons.edit,
                                            color: Colors.white30,
                                            size: 14,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Text(
                                          timeText,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 10,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              moneyText,
                                              style: const TextStyle(
                                                color: Color(0xFFF08080),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16, top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (dangChonXoa) {
                                  huyChonXoa();
                                } else {
                                  batDauChonXoa();
                                }
                              },
                              child: _circleBtn(
                                dangChonXoa
                                    ? Icons.close
                                    : Icons.delete_outline,
                                dangChonXoa
                                    ? const Color(0xFF555555)
                                    : (danhSachChi.isEmpty
                                        ? const Color(0xFF333333)
                                        : const Color(0xFFE57373)),
                                colorIcon: danhSachChi.isEmpty && !dangChonXoa
                                    ? Colors.white38
                                    : Colors.white,
                              ),
                            ),
                            const SizedBox(width: 24),
                            GestureDetector(
                              onTap: dangChonXoa ? null : themChiTieu,
                              child: _circleBtn(
                                Icons.add,
                                dangChonXoa
                                    ? const Color(0xFF333333)
                                    : const Color(0xFF4CAF93),
                                colorIcon:
                                    dangChonXoa ? Colors.white38 : Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color bg, {Color colorIcon = Colors.white}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: colorIcon, size: 22),
    );
  }
}

// =================== XÁC NHẬN XÓA KHÁC SCREEN ===================

class XacNhanXoaKhacScreen extends StatelessWidget {
  final int soTien;
  final String tenChiTieu;

  const XacNhanXoaKhacScreen({
    super.key,
    required this.soTien,
    required this.tenChiTieu,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            const _WatchBackground(),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _appLanguage == 'vi' ? 'Xóa khoản chi' : 'Delete expense',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tenChiTieu,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        formatAmountWithCurrency(soTien),
                        style: const TextStyle(
                          color: Color(0xFFF08080),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context, true),
                          child: _circleBtn(
                              Icons.delete_outline, const Color(0xFFE57373)),
                        ),
                        const SizedBox(width: 32),
                        GestureDetector(
                          onTap: () => Navigator.pop(context, false),
                          child:
                              _circleBtn(Icons.close, const Color(0xFF666666)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

// =================== NHẬP CHI TIÊU KHÁC SCREEN ===================

class NhapChiTieuKhacScreen extends StatefulWidget {
  final String? tenBanDau;
  final int? soTienBanDau;

  const NhapChiTieuKhacScreen({
    super.key,
    this.tenBanDau,
    this.soTienBanDau,
  });

  @override
  State<NhapChiTieuKhacScreen> createState() => _NhapChiTieuKhacScreenState();
}

class _NhapChiTieuKhacScreenState extends State<NhapChiTieuKhacScreen> {
  late final TextEditingController _tenController;
  late final TextEditingController _soTienController;
  final FocusNode _tenFocusNode = FocusNode();
  final FocusNode _soTienFocusNode = FocusNode();

  bool get isEdit => widget.tenBanDau != null || widget.soTienBanDau != null;

  @override
  void initState() {
    super.initState();
    _tenController = TextEditingController(text: widget.tenBanDau ?? '');
    _soTienController = TextEditingController(
      text: widget.soTienBanDau != null ? widget.soTienBanDau.toString() : '',
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tenFocusNode.requestFocus();
        if (isEdit && _tenController.text.isNotEmpty) {
          _tenController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _tenController.text.length,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _tenController.dispose();
    _soTienController.dispose();
    _tenFocusNode.dispose();
    _soTienFocusNode.dispose();
    super.dispose();
  }

  void _xacNhan() {
    final ten = _tenController.text.trim();
    final soTienText = _soTienController.text.trim();
    
    if (ten.isEmpty || soTienText.isEmpty) {
      return;
    }

    final soTien = int.tryParse(soTienText);
    if (soTien == null || soTien <= 0) {
      return;
    }

    Navigator.pop(context, {
      'tenChiTieu': ten,
      'soTien': soTien,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            const _WatchBackground(),
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isEdit 
                          ? (_appLanguage == 'vi' ? 'Sửa chi tiêu' : 'Edit expense')
                          : (_appLanguage == 'vi' ? 'Thêm chi tiêu khác' : 'Add expense'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 0),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: TextField(
                        focusNode: _tenFocusNode,
                        controller: _tenController,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: _appLanguage == 'vi' ? 'Tên chi tiêu' : 'Expense name',
                          hintStyle: TextStyle(color: Colors.white24, fontSize: 14),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 30),
                      child: TextField(
                        focusNode: _soTienFocusNode,
                        controller: _soTienController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(
                          color: Color(0xFFF08080),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: _appLanguage == 'vi' ? 'Số tiền' : 'Amount',
                          hintStyle: TextStyle(color: Colors.white24, fontSize: 18),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFF08080)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: _circleBtn(Icons.close, const Color(0xFF555555)),
                        ),
                        const SizedBox(width: 32),
                        GestureDetector(
                          onTap: _xacNhan,
                          child: _circleBtn(Icons.check, const Color(0xFF4CAF93)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, Color color) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

// =================== SETTINGS SCREEN ===================

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onLanguageChanged;
  
  const SettingsScreen({super.key, this.onLanguageChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _selectedLanguage;
  late String _selectedCurrency;
  bool _languageExpanded = false;
  bool _currencyExpanded = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _selectedLanguage = _appLanguage;
    _selectedCurrency = _appCurrency;
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = info.version;
      });
    }
  }

  Future<void> _setLanguage(String lang) async {
    if (_selectedLanguage == lang) return;
    
    setState(() {
      _selectedLanguage = lang;
      _languageExpanded = false;
    });
    
    _appLanguage = lang;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_keyLanguage, lang);
    widget.onLanguageChanged?.call();
  }

  Future<void> _setCurrency(String currency) async {
    if (_selectedCurrency == currency) return;
    
    setState(() {
      _selectedCurrency = currency;
      _currencyExpanded = false;
    });
    
    _appCurrency = currency;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(_keyCurrency, currency);
    await prefs.setString('app_currency', currency); // Also save without prefix for Tile/Complication
    await prefs.setDouble('exchange_rate', _exchangeRate);
    
    // Fetch exchange rate when switching to USD
    if (currency == '\$') {
      await fetchExchangeRate();
      // Save new rate
      await prefs.setDouble('exchange_rate', _exchangeRate);
    }
    
    // First, refresh parent to update currency display AND save data
    widget.onLanguageChanged?.call();
    
    // Small delay to ensure data is written before triggering update
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Then trigger complication update with fresh data
    try {
      const channel = MethodChannel('com.chiscung.quanlychitieu/complication');
      await channel.invokeMethod('updateComplication');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final edge = (MediaQuery.of(context).size.width * 0.10).clamp(16.0, 36.0);
    final isVietnamese = _selectedLanguage == 'vi';

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            const _WatchBackground(),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Real-time clock at top
                  const SizedBox(height: 4),
                  const ClockText(
                    showSeconds: false,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.settings_rounded, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        isVietnamese ? 'Cài đặt' : 'Settings',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Language Section - Click to expand
                  GestureDetector(
                    onTap: () => setState(() {
                      _languageExpanded = !_languageExpanded;
                      if (_languageExpanded) _currencyExpanded = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: _languageExpanded 
                            ? Border.all(color: const Color(0xFF4CAF93), width: 1)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.language_rounded, color: Colors.white70, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isVietnamese ? 'Ngôn ngữ' : 'Language',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                _selectedLanguage == 'vi' ? '🇻🇳 VI' : '🇺🇸 EN',
                                style: const TextStyle(
                                  color: Color(0xFF4CAF93),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _languageExpanded ? Icons.expand_less : Icons.expand_more,
                                color: Colors.white54,
                                size: 18,
                              ),
                            ],
                          ),
                          if (_languageExpanded) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _optionButton(
                                    '🇻🇳',
                                    'Tiếng Việt',
                                    _selectedLanguage == 'vi',
                                    () => _setLanguage('vi'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _optionButton(
                                    '🇺🇸',
                                    'English',
                                    _selectedLanguage == 'en',
                                    () => _setLanguage('en'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Currency Section - Click to expand
                  GestureDetector(
                    onTap: () => setState(() {
                      _currencyExpanded = !_currencyExpanded;
                      if (_currencyExpanded) _languageExpanded = false;
                    }),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                        border: _currencyExpanded 
                            ? Border.all(color: const Color(0xFF4CAF93), width: 1)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.attach_money_rounded, color: Colors.white70, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isVietnamese ? 'Tiền tệ' : 'Currency',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                _selectedCurrency == 'đ' ? '₫ VND' : '\$ USD',
                                style: const TextStyle(
                                  color: Color(0xFF4CAF93),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _currencyExpanded ? Icons.expand_less : Icons.expand_more,
                                color: Colors.white54,
                                size: 18,
                              ),
                            ],
                          ),
                          if (_currencyExpanded) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _optionButton(
                                    '₫',
                                    'VND',
                                    _selectedCurrency == 'đ',
                                    () => _setCurrency('đ'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _optionButton(
                                    '\$',
                                    'USD',
                                    _selectedCurrency == '\$',
                                    () => _setCurrency('\$'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Version/Profile Section
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          backgroundColor: Colors.grey[900],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipOval(
                                  child: Image.asset(
                                    'assets/icon/app_icon.png',
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'VFinance',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'v$_appVersion',
                                  style: const TextStyle(
                                    color: Color(0xFF4CAF93),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isVietnamese 
                                      ? 'Quản lý chi tiêu trên Wear OS\nPhát triển bởi © 2025-vochicuongg.'
                                      : 'Expense Manager on Wear OS\nDeveloped by © 2025-vochicuongg.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 8,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => Navigator.pop(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4CAF93),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      isVietnamese ? 'Đóng' : 'Close',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isVietnamese ? 'Thông tin' : 'Information',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white54,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // QR Code Section - Compact
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_rounded, color: Colors.white70, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              isVietnamese ? 'Liên hệ' : 'Contact',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.asset(
                              'assets/images/qr_code.png',
                              width: 60,
                              height: 60,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'vochicuong.id.vn',
                          style: TextStyle(
                            color: Color(0xFF4CAF93),
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            // Back button
            Positioned(
              top: 8,
              left: edge,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white70,
                  size: 14,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionButton(String emoji, String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected 
              ? const Color(0xFF4CAF93).withOpacity(0.3) 
              : Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: const Color(0xFF4CAF93), width: 1.5)
              : null,
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: selected ? const Color(0xFF4CAF93) : Colors.white70,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
