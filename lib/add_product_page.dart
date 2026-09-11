import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final _nameController = TextEditingController();
  final _qtyController = TextEditingController();
  final _minStockController = TextEditingController();
  final ScreenshotController _screenshotController = ScreenshotController();

  String? _productId;
  String? _selectedCategory;
  String? _savedFilePath;

  final List<String> _categories = [
    'Writing Instruments',
    'Paper Products',
    'Desk Supplies',
    'Folders & Organizers',
    'Art & Presentation Supplies',
    'Technology Accessories',
    'Labeling & Identification',
    'Mailing & Shipping',
    'Cleaning & Maintenance',
  ];

  Future<void> _saveProduct() async {
    if (_nameController.text.isEmpty ||
        _qtyController.text.isEmpty ||
        _minStockController.text.isEmpty ||
        _selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all fields and select a category'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final quantity = int.tryParse(_qtyController.text);
    final minStock = int.tryParse(_minStockController.text);

    if (quantity == null || minStock == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quantity and Min Stock must be numbers'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      final productName = _nameController.text;


      final existing = await Supabase.instance.client
          .from('products')
          .select('id')
          .ilike('name', productName)
          .eq('is_deleted', false)
          .maybeSingle();

      if (existing != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product with this name already exists!'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }


      _productId = 'PROD-${Uuid().v4().substring(0, 6).toUpperCase()}';

      await Supabase.instance.client.from('products').insert({
        'id': _productId,
        'name': productName,
        'quantity': quantity,
        'min_stock': minStock,
        'category': _selectedCategory,
        'updated_at': DateTime.now().toIso8601String(),
      });

      await Supabase.instance.client.from('transactions').insert({
        'product_id': _productId,
        'type': 'ADDED',
        'amount': quantity,
      });

      final qrWidget = Container(
        color: Colors.white,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: _productId!,
              size: 200,
            ),
            const SizedBox(height: 10),
            Text(
              _productId!,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      );

      final image = await _screenshotController.captureFromWidget(
        qrWidget,
        delay: const Duration(milliseconds: 100),
      );

      final directory = await getExternalStorageDirectory();
      final folder = Directory('${directory!.path}/IOT_Inventory');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final file = await File('${folder.path}/$_productId.png').create();
      await file.writeAsBytes(image);

      setState(() {
        _savedFilePath = file.path;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product saved! File location:\n${_savedFilePath}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );

        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving product: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Product')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Product Name'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Category'),
              value: _selectedCategory,
              items: _categories
                  .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value;
                });
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Initial Quantity'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _minStockController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Min Stock Alert'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saveProduct,
              child: const Text('Save Product & Generate QR'),
            ),
          ],
        ),
      ),
    );
  }
}
