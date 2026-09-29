import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'models.dart';
import 'receipt_scanner.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpendingApp());
}

ThemeData _theme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff166b59),
    brightness: brightness,
  ),
  inputDecorationTheme: const InputDecorationTheme(
    border: OutlineInputBorder(),
  ),
);

class SpendingApp extends StatelessWidget {
  const SpendingApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Macro Spending',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.openStore = SpendingStore.open});
  final Future<SpendingStore> Function() openStore;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  SpendingStore? _store;
  List<LedgerEntry> _entries = [];
  List<MonthlyRule> _rules = [];
  String? _error;
  bool _loading = true;
  int _tab = 0;
  final _scanner = ReceiptScanner();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _store?.db.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) _load();
  }

  Future<void> _load() async {
    final firstLoad = _store == null;
    try {
      _store ??= await widget.openStore();
      await _store!.materialize(DateTime.now());
      final entries = await _store!.entries();
      final rules = await _store!.rules();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _rules = rules;
        _error = null;
        _loading = false;
      });
      if (firstLoad && Platform.isAndroid) {
        try {
          final draft = await _scanner.recover();
          if (draft != null && mounted) await _add(draft: draft);
        } catch (_) {
          if (mounted) {
            _message(
              'Could not recover the receipt photo. Please try scanning again.',
            );
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your data. Please try again.';
          _loading = false;
        });
      }
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _add({
    bool recurring = false,
    ReceiptDraft? draft,
    LedgerEntry? entry,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EntryForm(
          store: _store!,
          recurring: recurring,
          draft: draft,
          entry: entry,
          categories: _categories,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(LedgerEntry entry) async {
    // Dismissible requires the tile to leave the tree immediately.
    setState(() => _entries.remove(entry));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _store!.delete(entry.id);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted ${entry.business}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                await _store!.restore(entry.id);
              } catch (_) {
                if (mounted) _message('Could not restore. Please try again.');
              }
              await _load();
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) _message('Could not delete. Please try again.');
    }
    await _load();
  }

  /// Distinct categories, case-insensitive, most recently used first.
  List<String> get _categories {
    final seen = <String, String>{};
    for (final category in [
      ..._entries.map((e) => e.category),
      ..._rules.map((r) => r.category),
    ]) {
      seen.putIfAbsent(category.toLowerCase(), () => category);
    }
    return seen.values.toList();
  }

  Future<void> _stop(MonthlyRule rule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop monthly entry?'),
        content: Text(
          'Stop future entries for ${rule.business}? Existing history will stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _store!.stopRule(rule.id);
      await _load();
    } catch (_) {
      if (mounted) {
        _message('Could not stop this monthly entry. Please try again.');
      }
    }
  }

  List<LedgerEntry> get _posted =>
      _entries.where((entry) => !entry.date.isAfter(DateTime.now())).toList();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        [
          'Macro Spending',
          'Your history',
          'Monthly entries',
          'Statistics',
        ][_tab],
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              children: switch (_tab) {
                0 => _overview(),
                1 => [
                  const Text('All transactions · USD'),
                  const SizedBox(height: 16),
                  if (_entries.isEmpty)
                    const _Empty(
                      'Your history starts with your first receipt.',
                    ),
                  ..._entries.map(_entryTile),
                ],
                2 => _monthly(),
                _ => _statistics(),
              },
            ),
          ),
    floatingActionButton: _store == null || _error != null
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _add(recurring: _tab == 2),
            icon: const Icon(Icons.add),
            label: Text(_tab == 2 ? 'Monthly entry' : 'Add transaction'),
          ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (value) => setState(() => _tab = value),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          label: 'Overview',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          label: 'History',
        ),
        NavigationDestination(icon: Icon(Icons.repeat), label: 'Monthly'),
        NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Statistics'),
      ],
    ),
  );

  List<Widget> _overview() {
    final now = DateTime.now();
    final month = _posted.where(
      (e) => e.date.year == now.year && e.date.month == now.month,
    );
    final spent = month
        .where((e) => e.kind == EntryKind.expense)
        .fold(0, (sum, e) => sum + e.cents);
    final earned = month
        .where((e) => e.kind == EntryKind.income)
        .fold(0, (sum, e) => sum + e.cents);
    final balance = _posted.fold(
      0,
      (sum, e) => sum + (e.kind == EntryKind.income ? e.cents : -e.cents),
    );
    return [
      Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Recorded balance · USD'),
              const SizedBox(height: 8),
              Text(
                money(balance),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text('Income minus expenses recorded in this app.'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 24,
        runSpacing: 12,
        children: [
          Text(
            'Spent this month\n${money(spent)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'Income this month\n${money(earned)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
      const SizedBox(height: 28),
      Text('Recent activity', style: Theme.of(context).textTheme.titleLarge),
      if (_entries.isEmpty)
        const _Empty(
          'Add a receipt or income to get started. Your data stays on this device.',
        ),
      ..._posted.take(5).map(_entryTile),
    ];
  }

  Widget _entryTile(LedgerEntry entry) {
    final colors = Theme.of(context).colorScheme;
    final income = entry.kind == EntryKind.income;
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: colors.errorContainer,
        child: Icon(Icons.delete_outline, color: colors.onErrorContainer),
      ),
      onDismissed: (_) => _delete(entry),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: () => _add(entry: entry),
        leading: CircleAvatar(
          child: Icon(income ? Icons.south_west : Icons.north_east),
        ),
        title: Text(entry.business),
        subtitle: Text(
          '${entry.category} · ${dateKey(entry.date)}${entry.date.isAfter(DateTime.now()) ? ' · Scheduled' : ''}',
        ),
        trailing: Text(
          '${income ? '+' : '-'}${money(entry.cents)}',
          style: TextStyle(color: income ? colors.primary : colors.error),
        ),
      ),
    );
  }

  List<Widget> _monthly() => [
    const Text(
      'Monthly income and expenses post on their start day. Short months use the last day.',
    ),
    const SizedBox(height: 16),
    if (_rules.isEmpty)
      const _Empty('Add your salary, rent, or other monthly transactions.'),
    for (final rule in _rules)
      Card(
        child: ListTile(
          title: Text(rule.business),
          subtitle: Text(
            '${rule.kind.label} · ${rule.category} · ${money(rule.cents)} / month\nStarts ${dateKey(rule.start)}',
          ),
          isThreeLine: true,
          trailing: IconButton(
            tooltip: 'Stop monthly entry',
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: () => _stop(rule),
          ),
        ),
      ),
  ];

  List<Widget> _statistics() {
    final now = DateTime.now();
    // Group case-insensitively; label with the most recent spelling.
    final totals = <String, int>{};
    final labels = <String, String>{};
    for (final entry in _posted.where(
      (e) => e.kind == EntryKind.expense && e.date.year == now.year,
    )) {
      final key = entry.category.toLowerCase();
      labels.putIfAbsent(key, () => entry.category);
      totals.update(
        labels[key]!,
        (sum) => sum + entry.cents,
        ifAbsent: () => entry.cents,
      );
    }
    final categories = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sum = totals.values.fold(0, (a, b) => a + b);
    return [
      Text(
        'Spending in ${now.year}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(money(sum), style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 24),
      if (categories.isEmpty)
        const _Empty(
          'Your spending breakdown will appear after you add an expense.',
        ),
      for (final category in categories)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${category.key} · ${money(category.value)} · ${(category.value / sum * 100).toStringAsFixed(0)}%',
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: category.value / sum,
                minHeight: 12,
                // Semantics value must be numeric (0–100), so the amount
                // goes in the label.
                semanticsLabel: '${category.key}, ${money(category.value)}',
                semanticsValue: (category.value / sum * 100).round().toString(),
              ),
            ],
          ),
        ),
    ];
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );
}

class EntryForm extends StatefulWidget {
  const EntryForm({
    super.key,
    required this.store,
    required this.recurring,
    this.draft,
    this.entry,
    this.categories = const [],
  });
  final SpendingStore store;
  final bool recurring;
  final ReceiptDraft? draft;

  /// Existing entry to edit; null when adding.
  final LedgerEntry? entry;

  /// Previously used categories, offered as suggestions.
  final List<String> categories;
  @override
  State<EntryForm> createState() => _EntryFormState();
}

class _EntryFormState extends State<EntryForm> {
  final _form = GlobalKey<FormState>();
  final _business = TextEditingController();
  final _category = TextEditingController();
  final _categoryFocus = FocusNode();
  final _amount = TextEditingController();
  var _date = DateTime.now();
  var _kind = EntryKind.expense;
  bool _busy = false;
  String? _error;
  String? _scanText;

  bool get _editing => widget.entry != null;

  // Monthly entries keep their due date; see SpendingStore.update.
  bool get _dateLocked => widget.entry?.ruleId != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    if (entry != null) {
      _business.text = entry.business;
      _category.text = entry.category;
      _amount.text = (entry.cents / 100).toStringAsFixed(2);
      _date = entry.date;
      _kind = entry.kind;
    }
    if (widget.draft != null) _applyDraft(widget.draft!);
  }

  void _applyDraft(ReceiptDraft draft) {
    _business.text = draft.business;
    _amount.text = draft.amount ?? '';
    _scanText = draft.rawText;
  }

  @override
  void dispose() {
    _business.dispose();
    _category.dispose();
    _categoryFocus.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _scan(ImageSource source) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final draft = await ReceiptScanner().capture(source);
      if (mounted && draft != null) setState(() => _applyDraft(draft));
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not read the receipt. Check camera/photo access, try another photo, or enter it manually.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entry = widget.entry;
      if (entry != null) {
        await widget.store.update(
          entry.id,
          business: _business.text,
          category: _category.text,
          cents: parseCents(_amount.text)!,
          date: _date,
          kind: _kind,
        );
      } else {
        await widget.store.add(
          business: _business.text,
          category: _category.text,
          cents: parseCents(_amount.text)!,
          date: _date,
          kind: _kind,
          recurring: widget.recurring,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not save. Your form is still here; please try again.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? 'Edit transaction'
              : widget.recurring
              ? 'New monthly entry'
              : 'New transaction',
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SegmentedButton<EntryKind>(
              segments: const [
                ButtonSegment(
                  value: EntryKind.expense,
                  label: Text('Expense'),
                  icon: Icon(Icons.north_east),
                ),
                ButtonSegment(
                  value: EntryKind.income,
                  label: Text('Income'),
                  icon: Icon(Icons.south_west),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: _busy
                  ? null
                  : (value) => setState(() => _kind = value.first),
            ),
            const SizedBox(height: 20),
            if (!widget.recurring &&
                !_editing &&
                _kind == EntryKind.expense) ...[
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _scan(ImageSource.camera),
                    icon: const Icon(Icons.document_scanner_outlined),
                    label: const Text('Scan receipt'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _scan(ImageSource.gallery),
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('Choose photo'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            if (_scanText != null) ...[
              const Text(
                'Review the scanned details and choose the receipt date before saving.',
              ),
              ExpansionTile(
                title: const Text('Recognized text'),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      _scanText!.isEmpty ? 'No text found.' : _scanText!,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _business,
              enabled: !_busy,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Business or source',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a business or source'
                  : null,
            ),
            const SizedBox(height: 16),
            RawAutocomplete<String>(
              textEditingController: _category,
              focusNode: _categoryFocus,
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                return widget.categories.where(
                  (c) =>
                      c.toLowerCase().contains(query) &&
                      c.toLowerCase() != query,
                );
              },
              fieldViewBuilder: (context, controller, focusNode, _) =>
                  TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      hintText: 'Groceries, rent, salary…',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a category'
                        : null,
                  ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 240,
                      maxWidth: 320,
                    ),
                    child: ListView(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      children: [
                        for (final option in options)
                          ListTile(
                            title: Text(option),
                            onTap: () => onSelected(option),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount (USD)',
                prefixText: '\$ ',
              ),
              validator: (value) => parseCents(value ?? '') == null
                  ? 'Enter a positive amount with up to two decimal places'
                  : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(widget.recurring ? 'Start date' : 'Transaction date'),
              subtitle: Text(
                _dateLocked
                    ? '${dateKey(_date)} · Set by monthly entry'
                    : dateKey(_date),
              ),
              trailing: const Icon(Icons.calendar_month),
              enabled: !_dateLocked,
              onTap: _busy || _dateLocked
                  ? null
                  : () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(DateTime.now().year + 10, 12, 31),
                      );
                      if (date != null && mounted) setState(() => _date = date);
                    },
            ),
            if (widget.recurring)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Past start dates add each monthly transaction through today.',
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    ),
  );
}
