import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ChiTieuApp(),
    ),
  );
}

// =================== UTILS ===================

String dinhDangSo(int value) {
  return value.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
}

String dinhDangGio(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// Hiển thị ngày tháng năm đầy đủ (dd/MM/yyyy)
String dinhDangNgayDayDu(DateTime time) {
  final d = time.day.toString().padLeft(2, '0');
  final mo = time.month.toString().padLeft(2, '0');
  final y = time.year.toString();
  return '$d/$mo/$y';
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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
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

  ChiTieuItem({
    required this.soTien,
    required this.thoiGian,
  });

  ChiTieuItem copyWith({int? soTien, DateTime? thoiGian}) {
    return ChiTieuItem(
      soTien: soTien ?? this.soTien,
      thoiGian: thoiGian ?? this.thoiGian,
    );
  }
}

// =================== CATEGORY ===================

enum ChiTieuMuc { nhaTro, hocPhi, thucAn, doUong, xang, muaSam }

extension ChiTieuMucX on ChiTieuMuc {
  String get ten {
    switch (this) {
      case ChiTieuMuc.nhaTro:
        return 'Nhà trọ';
      case ChiTieuMuc.hocPhi:
        return 'Học phí';
      case ChiTieuMuc.thucAn:
        return 'Thức ăn';
      case ChiTieuMuc.doUong:
        return 'Đồ uống';
      case ChiTieuMuc.xang:
        return 'Xăng';
      case ChiTieuMuc.muaSam:
        return 'Mua sắm';
    }
  }

  IconData get icon {
    switch (this) {
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
    }
  }
}

// =================== BACKGROUND ===================

class _WatchBackground extends StatelessWidget {
  const _WatchBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.35),
          radius: 1,
          colors: [Color(0xFF000000), Colors.black],
        ),
      ),
    );
  }
}

// =================== HOME (GRID CATEGORIES) ===================

class ChiTieuApp extends StatefulWidget {
  const ChiTieuApp({super.key});

  @override
  State<ChiTieuApp> createState() => _ChiTieuAppState();
}

class _ChiTieuAppState extends State<ChiTieuApp> {
  final Map<ChiTieuMuc, List<ChiTieuItem>> _chiTheoMuc = {
    for (final muc in ChiTieuMuc.values) muc: <ChiTieuItem>[],
  };

  int _tongMuc(ChiTieuMuc muc) {
    final list = _chiTheoMuc[muc] ?? <ChiTieuItem>[];
    return list.fold(0, (a, b) => a + b.soTien);
  }

  int get _tongTatCaTrongThang {
    DateTime now = DateTime.now();
    int month = now.month;
    int year = now.year;

    return _chiTheoMuc.values.fold<int>(
      0,
      (sum, list) =>
          sum +
          list.fold<int>(
            0,
            (a, b) =>
                (b.thoiGian.month == month && b.thoiGian.year == year)
                    ? a + b.soTien
                    : a,
          ),
    );
  }

  Future<void> _moMuc(ChiTieuMuc muc) async {
    final updated = await Navigator.push<List<ChiTieuItem>>(
      context,
      MaterialPageRoute(
        builder: (_) => ChiTieuTheoMucScreen(
          muc: muc,
          danhSachChiBanDau: _chiTheoMuc[muc] ?? const <ChiTieuItem>[],
        ),
      ),
    );

    if (updated != null) {
      setState(() => _chiTheoMuc[muc] = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    final currentMonth = now.month;

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
                    // ✅ Màn hình chính: padding top 4
                    const SizedBox(height: 4),
                    const ClockText(showSeconds: false),
                    const SizedBox(height: 6),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: edge),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Tổng chi tiêu Tháng $currentMonth:',
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
                    const SizedBox(height: 4),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: edge),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${dinhDangSo(_tongTatCaTrongThang)} đ',
                          style: const TextStyle(
                            color: Color(0xFFF08080),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _ScalingGrid(
                        edge: edge,
                        itemCount: ChiTieuMuc.values.length,
                        itemBuilder: (context, i) {
                          final muc = ChiTieuMuc.values[i];
                          final tongMuc = _tongMuc(muc);
                          return _CategoryButton(
                            icon: muc.icon,
                            tongTien: tongMuc,
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

// =================== SCALING GRID ===================

class _ScalingGrid extends StatefulWidget {
  final double edge;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const _ScalingGrid({
    required this.edge,
    required this.itemCount,
    required this.itemBuilder,
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.maxWidth - widget.edge * 2;
        final itemWidth = (gridWidth - _crossSpacing * (_crossAxisCount - 1)) /
            _crossAxisCount;
        final itemHeight = itemWidth / _childAspectRatio;
        final rowExtent = itemHeight + _mainSpacing;
        final viewportHeight = constraints.maxHeight;

        final edgeZone = (viewportHeight * 0.30).clamp(50.0, 120.0);

        const maxShrink = 0.18;
        const maxFade = 0.35;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final scrollOffset =
                _controller.hasClients ? _controller.offset : 0.0;

            return GridView.builder(
              controller: _controller,
              padding:
                  EdgeInsets.fromLTRB(widget.edge, 0, widget.edge, widget.edge),
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
                final row = index ~/ _crossAxisCount;
                final itemTop = row * rowExtent;
                final itemCenterY = itemTop + itemHeight / 2;

                final centerRel = itemCenterY - scrollOffset;

                double scale = 1.0;
                double opacity = 1.0;

                if (centerRel < edgeZone) {
                  final t = (1 - (centerRel / edgeZone)).clamp(0.0, 1.0);
                  scale = 1.0 - maxShrink * t;
                  opacity = 1.0 - maxFade * t;
                } else if (centerRel > viewportHeight - edgeZone) {
                  final distToBottom = viewportHeight - centerRel;
                  final t = (1 - (distToBottom / edgeZone)).clamp(0.0, 1.0);
                  scale = 1.0 - maxShrink * t;
                  opacity = 1.0 - maxFade * t;
                }

                return Transform.scale(
                  scale: scale,
                  alignment: Alignment.center,
                  child: Opacity(
                    opacity: opacity,
                    child: widget.itemBuilder(context, index),
                  ),
                );
              },
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

  const _CategoryButton({
    required this.icon,
    required this.tongTien,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool coTien = tongTien > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B1B),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
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
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${dinhDangSo(tongTien)} đ',
                      style: const TextStyle(
                        color: Color(0xFFF08080),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =================== CATEGORY DETAIL ===================

class ChiTieuTheoMucScreen extends StatefulWidget {
  final ChiTieuMuc muc;
  final List<ChiTieuItem> danhSachChiBanDau;

  const ChiTieuTheoMucScreen({
    super.key,
    required this.muc,
    required this.danhSachChiBanDau,
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
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(item);
    }

    for (var entry in grouped.entries) {
      final dateString = entry.key;
      final dailyList = entry.value;
      final dailySum = dailyList.fold(0, (sum, item) => sum + item.soTien);

      rows.add(_ListRow.header(dateString, dailySum));
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
        danhSachChi.add(ChiTieuItem(soTien: soTien, thoiGian: DateTime.now()));
      });
    }
  }

  Future<void> chinhSuaChiTieu(int index) async {
    if (dangChonXoa) return;

    final soTienMoi = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NhapSoTienScreen(soTienBanDau: danhSachChi[index].soTien),
      ),
    );

    if (soTienMoi != null && soTienMoi > 0) {
      setState(() {
        danhSachChi[index] = danhSachChi[index].copyWith(
          soTien: soTienMoi,
          thoiGian: DateTime.now(),
        );
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
                          Navigator.pop(context, danhSachChi);
                        }
                      },
                    ),
                  ),
                  Column(
                    children: [
                      // ✅ Màn hình chi tiết: Sửa padding top từ 10 thành 4 để khớp màn hình chính
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
                            '${dinhDangSo(tongChi)} đ',
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      row.dateHeader!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      '${dinhDangSo(row.dailyTotal!)} đ',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final item = row.item!;
                            final timeText = dinhDangGio(item.thoiGian);
                            final moneyText = '${dinhDangSo(item.soTien)} đ';
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

  const XacNhanXoaScreen({super.key, required this.soTien});

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
                    const Text(
                      'Bạn có muốn xóa khoản chi',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 0),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${dinhDangSo(soTien)} đ',
                        style: const TextStyle(
                          color: Color(0xFFF08080),
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 0),
                    const Text(
                      'này không?',
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

    final initText =
        widget.soTienBanDau != null ? widget.soTienBanDau.toString() : '';
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
                    isEdit ? 'Sửa số tiền' : 'Nhập số tiền',
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
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                        color: Color(0xFFF08080),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        hintText: '0',
                        hintStyle: TextStyle(color: Colors.white24),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: UnderlineInputBorder(
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