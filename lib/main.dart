import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'transaction_page.dart';
import 'add_product_page.dart';
import 'scanner_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://sxuqsmotdadeqedscgzp.supabase.co',
    anonKey:
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InN4dXFzbW90ZGFkZXFlZHNjZ3pwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY2NDUwMTYsImV4cCI6MjA4MjIyMTAxNn0.JjGuHBnLIcpuwhIwOYHWblg9ZQyfnDnEXsxdFDNMstE',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IoT Inventory',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const DashboardPage(),
    );
  }
}

enum DashboardView { none, allItems, lowStock, analytics }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;
  DashboardView _selectedView = DashboardView.allItems;

  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];

  bool _loading = true;
  late RealtimeChannel _realtimeChannel;

  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  @override
  void initState() {
    super.initState();

    _initNotifications();
    _fetchProducts();
    _initRealtime();
  }

  @override
  void dispose() {
    Supabase.instance.client.removeChannel(_realtimeChannel);
    super.dispose();
  }

  Future<void> _fetchProducts() async {
    final data = await Supabase.instance.client
        .from('products')
        .select()
        .eq('is_deleted', false)
        .order('name');

    if (!mounted) return;

    final visibleProducts = (data as List)
        .cast<Map<String, dynamic>>()
        .where((p) => p['is_deleted'] != true)
        .toList();

    setState(() {
      _products = visibleProducts;
      _filteredProducts = List.from(_products);
      _loading = false;
    });

    _checkLowStock(_products);
  }

  void _initRealtime() {
    _realtimeChannel = Supabase.instance.client
        .channel('public:products')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'products',
      callback: (_) => _fetchProducts(),
    )
        .subscribe();
  }

  void _initNotifications() async {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload == 'low_stock') {
          setState(() {
            _selectedView = DashboardView.lowStock;
          });
        }
      },
    );
  }

  void _checkLowStock(List<Map<String, dynamic>> products) {
    for (var p in products) {
      if (p['quantity'] <= p['min_stock']) {
        _showNotification(
          title: 'Low Stock Alert',
          body: '${p['name']} is low on stock!',
        );
      }
    }
  }

  void _showNotification({required String title, required String body}) async {
    const AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'low_stock_channel',
      'Low Stock Notifications',
      channelDescription: 'Notifications when product stock is low',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformDetails =
    NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformDetails,
      payload: 'low_stock',
    );
  }

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _onNavTapped(int index) async {
    setState(() => _selectedIndex = index);

    switch (index) {
      case 0:
        _selectedView = DashboardView.allItems;
        _filteredProducts = List.from(_products);
        break;

      case 1:
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TransactionsPage()),
        );
        break;

      case 2:
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddProductPage()),
        );
        if (result == true) _fetchProducts();
        break;
    }
  }

  Future<void> exportInventoryCSV(BuildContext context) async {
    try {
      final supabase = Supabase.instance.client;

      final List productsData = await supabase
          .from('products')
          .select('id, name, category, quantity, min_stock, updated_at')
          .eq('is_deleted', false)
          .order('name');

      String productsCsv = 'ID,Name,Category,Quantity,Minimum Stock,Last Updated\n';
      for (final p in productsData) {
        productsCsv +=
        '${p['id']},${p['name']},${p['category'] ?? ''},${p['quantity']},${p['min_stock']},${p['updated_at']}\n';
      }

      final List transactionsData = await supabase
          .from('transactions')
          .select('id, product_id, type, amount, created_at, products(name)')
          .order('created_at', ascending: false);

      String transactionsCsv = 'ID,Product ID,Product Name,Type,Amount,Created At\n';
      for (final t in transactionsData) {
        final productName = t['products']?['name'] ?? 'Unknown';
        transactionsCsv +=
        '${t['id']},${t['product_id']},$productName,${t['type']},${t['amount']},${t['created_at']}\n';
      }

      final status = await Permission.storage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Storage permission denied'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      final dir = await getExternalStorageDirectory();
      final ts = _timestamp();

      final productsFile =
      File('${dir!.path}/products_$ts.csv');

      final transactionsFile =
      File('${dir.path}/transactions_$ts.csv');


      await productsFile.writeAsString(productsCsv);
      await transactionsFile.writeAsString(transactionsCsv);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'CSV saved!\nProducts: ${productsFile.path}\nTransactions: ${transactionsFile.path}',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> confirmExportCSV(BuildContext context) async {
    final bool? proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Export Inventory'),
        content: const Text(
          'Do you want to download the inventory report as a CSV file?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      exportInventoryCSV(context);
    }
  }

  Map<String, int> _computeAnalytics(List<Map<String, dynamic>> products) {
    int totalProducts = products.length;
    int totalStocks = 0;
    int lowStockCount = 0;

    for (var p in products) {
      final qty = p['quantity'] as int;
      final min = p['min_stock'] as int;
      totalStocks += qty;
      if (qty <= min) lowStockCount++;
    }

    return {
      'totalProducts': totalProducts,
      'totalStocks': totalStocks,
      'lowStock': lowStockCount,
    };
  }

  Map<String, int> _computeCategoryTotals(List<Map<String, dynamic>> products) {
    final Map<String, int> totals = {};

    for (final p in products) {
      final category = p['category'] ?? 'Uncategorized';
      final qty = p['quantity'] as int;

      totals[category] = (totals[category] ?? 0) + qty;
    }

    return totals;
  }

  Map<String, int> _categoryTotals(List<Map<String, dynamic>> products) {
    final Map<String, int> totals = {};

    for (var p in products) {
      final category = p['category'] ?? 'Uncategorized';
      final qty = p['quantity'] as int;

      totals[category] = (totals[category] ?? 0) + qty;
    }

    return totals;
  }

  double _getNiceMaxY(int maxValue) {
    if (maxValue <= 100) return 100;

    if (maxValue < 1000) {
      return ((maxValue / 100).ceil() * 100).toDouble();
    } else {
      return ((maxValue / 1000).ceil() * 1000).toDouble();
    }
  }

  double _computeMaxY(Map<String, int> data) {
    if (data.isEmpty) return 200;

    final maxValue = data.values.reduce((a, b) => a > b ? a : b);

    final rounded = ((maxValue + 99) ~/ 100) * 100;

    return (rounded + 200).toDouble();
  }

  Widget _analyticsCards(
      Map<String, int> data, List<Map<String, dynamic>> products) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _statCard(
            title: 'Items',
            value: data['totalProducts'].toString(),
            color: Colors.blue,
            icon: Icons.category,
            onTap: () => setState(() => _selectedView = DashboardView.allItems),
          ),
          _statCard(
            title: 'Total Stock',
            value: data['totalStocks'].toString(),
            color: Colors.green,
            icon: Icons.bar_chart,
            onTap: () => setState(() => _selectedView = DashboardView.analytics),
          ),
          _statCard(
            title: 'Low Stock',
            value: data['lowStock'].toString(),
            color: Colors.red,
            icon: Icons.warning,
            onTap: () => setState(() => _selectedView = DashboardView.lowStock),
            badge: (data['lowStock'] ?? 0) > 0,
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    VoidCallback? onTap,
    bool badge = false,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        Center(
                          child: Icon(icon, color: color, size: 36),
                        ),
                        if (badge)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 0.5),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(fontSize: 14),
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

  Widget _buildContent(List<Map<String, dynamic>> products) {
    switch (_selectedView) {
      case DashboardView.allItems:
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search product name or ID',
                ),
                onChanged: (value) {
                  setState(() {
                    _filteredProducts = _products.where((p) {
                      final name = p['name'].toString().toLowerCase();
                      final id = p['id'].toString();
                      return name.contains(value.toLowerCase()) || id.contains(value);
                    }).toList();
                  });
                },
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _filteredProducts.length,
                itemBuilder: (_, index) {
                  final p = _filteredProducts[index];
                  final lowStock = p['quantity'] <= p['min_stock'];

                  return Dismissible(
                    key: Key(p['id']),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (direction) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Confirm Delete'),
                          content: Text(
                              'Are you sure you want to delete "${p['name']}"? This action cannot be undone.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Delete',
                                style: TextStyle(
                                    color: Colors.white
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    onDismissed: (direction) async {
                      final deletedProduct = Map<String, dynamic>.from(p);

                      await Supabase.instance.client
                          .from('products')
                          .update({'is_deleted': true})
                          .eq('id', p['id']);

                      await Supabase.instance.client.from('transactions').insert({
                        'product_id': p['id'],
                        'type': 'DELETED',
                        'amount': p['quantity'],
                      });

                      setState(() {
                        _products.removeWhere((item) => item['id'] == p['id']);
                        _filteredProducts.removeWhere((item) => item['id'] == p['id']);
                      });

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${p['name']} deleted'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    child: Card(
                      color: lowStock ? Colors.red[100] : Colors.white,
                      child: ListTile(
                        title: Text(
                          p['name'],
                          style: TextStyle(
                              fontWeight:
                              lowStock ? FontWeight.bold : FontWeight.normal),
                        ),
                        subtitle:
                        Text('Qty: ${p['quantity']} | Min: ${p['min_stock']}'),
                        trailing: lowStock
                            ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'LOW',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        )
                            : const Icon(Icons.check_circle, color: Colors.green),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );

      case DashboardView.lowStock:
        final lowStock = products.where((p) => p['quantity'] <= p['min_stock']).toList();
        return Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: lowStock.length,
            itemBuilder: (_, index) {
              final p = lowStock[index];
              return Dismissible(
                key: ValueKey(p['id']),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white, size: 30),
                ),
                confirmDismiss: (_) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete Product'),
                      content: Text('Are you sure you want to delete "${p['name']}"?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Delete',
                            style: TextStyle(
                                color: Colors.white
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (direction) async {
                  final deletedProduct = Map<String, dynamic>.from(p);

                  await Supabase.instance.client
                      .from('products')
                      .update({'is_deleted': true})
                      .eq('id', p['id']);

                  await Supabase.instance.client.from('transactions').insert({
                    'product_id': p['id'],
                    'type': 'DELETED',
                    'amount': p['quantity'],
                  });

                  setState(() {
                    _products.removeWhere((item) => item['id'] == p['id']);
                    _filteredProducts.removeWhere((item) => item['id'] == p['id']);
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${p['name']} deleted'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                },
                child: Card(
                  color: Colors.red[100],
                  child: ListTile(
                    title: Text(p['name']),
                    subtitle: Text('Qty: ${p['quantity']} | Min: ${p['min_stock']}'),
                  ),
                ),
              );
            },
          ),
        );

      case DashboardView.analytics:
        final categoryTotals = _computeCategoryTotals(products);

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Total Stock per Category',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(child: _categoryBarChart(categoryTotals)),
              ],
            ),
          ),
        );

      case DashboardView.none:
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('Inventory Dashboard')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
          ? const Center(child: Text('No products found'))
          : Column(
        children: [
          _analyticsCards(
            _computeAnalytics(_products),
            _products,
          ),
          const Divider(),
          Expanded(child: _buildContent(_products)),
        ],
      ),
      floatingActionButton: SizedBox(
        width: 70,
        height: 70,
        child: FloatingActionButton(
          backgroundColor: Colors.blue,
          elevation: 6,
          shape: const CircleBorder(),
          child: const Icon(
            Icons.qr_code_scanner,
            size: 45,
          ),
          onPressed: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ScannerPage()),
            );
            if (result == true) _fetchProducts();
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 10,
        height: 70,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.dashboard),
                  iconSize : 30,
                  onPressed: () => _onNavTapped(0),
                ),
                SizedBox(width: 20),
                IconButton(
                  icon: const Icon(Icons.list_alt),
                  iconSize : 30,
                  onPressed: () => _onNavTapped(1),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add),
                  iconSize : 30,
                  onPressed: () => _onNavTapped(2),
                ),
                SizedBox(width: 20),
                IconButton(
                  icon: const Icon(Icons.download),
                  iconSize : 30,
                    onPressed: () => confirmExportCSV(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryBarChart(Map<String, int> categoryTotals) {
    final categories = categoryTotals.keys.toList();
    final values = categoryTotals.values.toList();

    int rawMax = values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b);

    int roundedMax = ((rawMax + 99) ~/ 100) * 100;
    int maxY = roundedMax + 200;
    int step = 100;

    int longestLabelLength =
    categories.map((c) => c.length).reduce((a, b) => a > b ? a : b);

    double barSpacing = longestLabelLength > 20
        ? 120
        : longestLabelLength > 14
        ? 100
        : 80;

    Widget yAxisLabels() {
      return Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          (maxY ~/ step) + 1,
              (i) => Text(
            (maxY - (i * step)).toString(),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Padding(
          padding: const EdgeInsets.only(left: 8, right: 6),
          child: SizedBox(
            height: 260,
            child: yAxisLabels(),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.only(right: 24),
              child: SizedBox(
                height: 320,
                width: categories.length * barSpacing,
                child: BarChart(
                  BarChartData(
                    maxY: maxY.toDouble(),
                    barGroups: List.generate(categories.length, (index) {
                      return BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: values[index].toDouble(),
                            width: 26,
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      );
                    }),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 80,
                          getTitlesWidget: (value, meta) {
                            final idx = value.toInt();
                            if (idx < 0 || idx >= categories.length) {
                              return const SizedBox();
                            }

                            return SideTitleWidget(
                              axisSide: meta.axisSide,
                              space: 6,
                              child: SizedBox(
                                width: barSpacing - 10,
                                child: Text(
                                  categories[idx],
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                  maxLines: 4,
                                  overflow: TextOverflow.visible,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      leftTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles:
                      AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: step.toDouble(),
                    ),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        tooltipBgColor: Colors.black87,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                            rod.toY.toInt().toString(),
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
