import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  List<Map<String, dynamic>> _transactions = [];
  bool _loading = true;

  late RealtimeChannel _transactionChannel;

  @override
  void initState() {
    super.initState();
    _fetchTransactions();

    _transactionChannel = supabase.channel('public:transactions')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'transactions',
      callback: (_) => _fetchTransactions(),
    )
        .subscribe();
  }

  @override
  void dispose() {
    supabase.removeChannel(_transactionChannel);
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
    setState(() => _loading = true);

    try {
      final data = await supabase.from('transactions').select('''
          id,
          type,
          amount,
          created_at,
          products (
            name
          )
        ''')
          .order('created_at', ascending: false)
          .limit(50);

      if (!mounted) return;

      setState(() {
        _transactions = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading transactions: $e'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
          ? const Center(child: Text('No transactions found'))
          : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _transactions.length,
        itemBuilder: (context, index) {
          final transaction = _transactions[index];

          final productName =
              transaction['products']?['name'] ?? 'Unknown';
          final type = transaction['type'] ?? '';
          final qty = transaction['amount'] ?? 0;
          final time = transaction['created_at'] != null
              ? DateTime.parse(transaction['created_at']).toLocal()
              : null;

          IconData iconData;
          Color iconColor;

          switch (type.toUpperCase()) {
            case 'IN':
              iconData = Icons.arrow_downward;
              iconColor = Colors.green;
              break;
            case 'OUT':
              iconData = Icons.arrow_upward;
              iconColor = Colors.red;
              break;
            case 'ADDED':
              iconData = Icons.add_box;
              iconColor = Colors.blue;
              break;
            case 'DELETED':
              iconData = Icons.delete_forever;
              iconColor = Colors.grey;
              break;
            default:
              iconData = Icons.help_outline;
              iconColor = Colors.black;
          }

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 3,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              leading: Icon(iconData, color: iconColor, size: 32),
              title: Text(
                productName,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('Type: $type | Qty: $qty'),
                  if (time != null)
                    Text(
                      'Time: ${time.toString().substring(0, 19)}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
