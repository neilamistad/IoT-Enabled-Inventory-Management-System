import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool isScanned = false;
  String? transactionType;
  int quantity = 1;
  String? lastScannedId;

  final supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, true);
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan Item'),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ChoiceChip(
                    label: const Text('IN'),
                    selected: transactionType == 'IN',
                    selectedColor: Colors.green,
                    onSelected: (_) {
                      setState(() {
                        transactionType = 'IN';
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('OUT'),
                    selected: transactionType == 'OUT',
                    selectedColor: Colors.red,
                    onSelected: (_) {
                      setState(() {
                        transactionType = 'OUT';
                      });
                    },
                  ),
                ],
              ),
            ),

            if (transactionType == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Select IN or OUT before scanning',
                  style: TextStyle(color: Colors.red),
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 8),
              child: TextField(
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                controller: TextEditingController(text: quantity.toString()),
                onChanged: (value) {
                  final parsed = int.tryParse(value);
                  if (parsed != null && parsed > 0) {
                    setState(() => quantity = parsed);
                  } else {
                    setState(() => quantity = 1);
                  }
                },
              ),
            ),
            if (lastScannedId != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Last scanned: $lastScannedId (x$quantity)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),

            Expanded(
              child: MobileScanner(
                onDetect: (capture) async {
                  if (isScanned || transactionType == null) return;

                  final code = capture.barcodes.first.rawValue;
                  if (code == null) return;

                  setState(() => isScanned = true);

                  try {

                    final product = await supabase
                        .from('products')
                        .select('quantity')
                        .eq('id', code)
                        .single();

                    final currentQty = product['quantity'] as int;

                    if (transactionType == 'OUT' &&
                        currentQty < quantity) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Insufficient stock\nAvailable: $currentQty',
                          ),
                          backgroundColor: Colors.red,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );

                      setState(() => isScanned = false);
                      return;
                    }

                    final newQty = await supabase.rpc(
                      transactionType == 'IN'
                          ? 'increment_stock'
                          : 'decrement_stock',
                      params: {
                        'row_id': code,
                        'qty': quantity,
                      },
                    );

                    await supabase.from('transactions').insert({
                      'product_id': code,
                      'type': transactionType,
                      'amount': quantity,
                    });

                    if (!mounted) return;

                    setState(() {
                      lastScannedId = code;
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Success ($transactionType)\nNew stock: $newQty',
                        ),
                        backgroundColor: transactionType == 'IN'
                            ? Colors.green
                            : Colors.red,
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );

                    await Future.delayed(const Duration(seconds: 1));
                    setState(() {
                      isScanned = false;
                      transactionType = null;
                    });
                  } catch (e) {
                    setState(() => isScanned = false);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Scan failed:\n$e'),
                        backgroundColor: Colors.black,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );

                    debugPrint('Scan error: $e');
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
