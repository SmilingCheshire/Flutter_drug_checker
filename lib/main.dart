// lib/main.dart
// Flutter 3.x, Material 3, null-safety
// Pubspec: add http:^1.2.2 (or current) in dependencies
//
// name: drug_checker
// platforms: android, ios, web

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const DrugCheckerApp());
}

class DrugCheckerApp extends StatelessWidget {
  const DrugCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medical Drug Checker',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      home: const DrugSearchPage(),
    );
  }
}

class DrugInfo {
  final String displayName; // e.g., preferred brand or generic
  final String brandNames;
  final String genericNames;
  final String manufacturer;
  final String productType;
  final String? purpose;
  final String? indications;
  final String? warnings;
  final String? interactionsSection; // free-text from FDA label
  final bool found;

  DrugInfo({
    required this.displayName,
    required this.brandNames,
    required this.genericNames,
    required this.manufacturer,
    required this.productType,
    required this.purpose,
    required this.indications,
    required this.warnings,
    required this.interactionsSection,
    required this.found,
  });

  static DrugInfo notFound(String query) => DrugInfo(
        displayName: query,
        brandNames: '',
        genericNames: '',
        manufacturer: '',
        productType: '',
        purpose: null,
        indications: null,
        warnings: null,
        interactionsSection: null,
        found: false,
      );
}

class DrugSearchPage extends StatefulWidget {
  const DrugSearchPage({super.key});

  @override
  State<DrugSearchPage> createState() => _DrugSearchPageState();
}

class _DrugSearchPageState extends State<DrugSearchPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  DrugInfo? _currentDrug;
  final List<String> _selectedDrugs = [];

  Future<DrugInfo> _fetchDrugInfo(String query) async {
    final encoded = Uri.encodeQueryComponent(query);
    final search = 'openfda.brand_name:"$encoded"+OR+openfda.generic_name:"$encoded"';
    final url = Uri.parse(
        'https://api.fda.gov/drug/label.json?search=$search&limit=1');

    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        final jsonMap = json.decode(resp.body) as Map<String, dynamic>;
        final results = (jsonMap['results'] as List?) ?? [];

        if (results.isEmpty) {
          return DrugInfo.notFound(query);
        }

        final first = results.first as Map<String, dynamic>;

        // openfda subobject
        final openfda = (first['openfda'] ?? {}) as Map<String, dynamic>;
        String joinOrEmpty(dynamic v) =>
            v is List ? v.join(', ') : (v is String ? v : '');

        final brand = joinOrEmpty(openfda['brand_name']);
        final generic = joinOrEmpty(openfda['generic_name']);
        final mfr = joinOrEmpty(openfda['manufacturer_name']);
        final ptype = joinOrEmpty(openfda['product_type']);

        // Some label sections (arrays of strings)
        String? pickFirstLine(dynamic v) {
          if (v is List && v.isNotEmpty) return v.first.toString();
          if (v is String && v.trim().isNotEmpty) return v;
          return null;
        }

        final purpose = pickFirstLine(first['purpose']);
        final indications = pickFirstLine(first['indications_and_usage']);
        final warnings = pickFirstLine(first['warnings']);
        final interactionsTxt = pickFirstLine(first['drug_interactions']);

        // Choose a display name
        final display =
            (brand.isNotEmpty ? brand.split(',').first : '') // first brand
                .ifEmpty(() => generic.split(',').first.ifEmpty(() => query));

        return DrugInfo(
          displayName: display,
          brandNames: brand,
          genericNames: generic,
          manufacturer: mfr,
          productType: ptype,
          purpose: purpose,
          indications: indications,
          warnings: warnings,
          interactionsSection: interactionsTxt,
          found: true,
        );
      } else if (resp.statusCode == 404) {
        // openFDA returns 404 when no results
        return DrugInfo.notFound(query);
      } else {
        return DrugInfo.notFound(query);
      }
    } catch (_) {
      return DrugInfo.notFound(query);
    }
  }

  void _onSearch() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _isLoading = true;
      _currentDrug = null;
    });
    final info = await _fetchDrugInfo(q);
    setState(() {
      _currentDrug = info;
      _isLoading = false;
    });
  }

  void _addSelected() {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    if (!_selectedDrugs.contains(q)) {
      setState(() {
        _selectedDrugs.add(q);
      });
    }
  }

  void _removeSelected(String name) {
    setState(() {
      _selectedDrugs.remove(name);
    });
  }

  void _goToInteractions() {
    if (_selectedDrugs.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InteractionsPage(selectedDrugs: _selectedDrugs),
      ),
    );
  }

  Widget _buildDrugPanel() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_currentDrug == null) {
      return const SizedBox.shrink();
    }
    if (!_currentDrug!.found) {
      return _InfoCard(
        title: 'Not found in openFDA',
        lines: [
          'We couldn’t find this drug in the FDA Label API.',
          'Try a different spelling, a brand name, or a generic name.',
        ],
        statusIcon: Icons.error_outline,
      );
    }
    final d = _currentDrug!;
    return _InfoCard(
      title: d.displayName,
      badge: 'Found in FDA Label API',
      lines: [
        if (d.brandNames.isNotEmpty) 'Brand: ${d.brandNames}',
        if (d.genericNames.isNotEmpty) 'Generic: ${d.genericNames}',
        if (d.manufacturer.isNotEmpty) 'Manufacturer: ${d.manufacturer}',
        if (d.productType.isNotEmpty) 'Product Type: ${d.productType}',
        if (d.purpose?.isNotEmpty == true) '\nPurpose:\n${d.purpose}',
        if (d.indications?.isNotEmpty == true)
          '\nIndications & Usage:\n${d.indications}',
        if (d.warnings?.isNotEmpty == true) '\nWarnings:\n${d.warnings}',
        if (d.interactionsSection?.isNotEmpty == true)
          '\nLabel “Drug Interactions” (free text):\n${d.interactionsSection}',
      ],
      statusIcon: Icons.verified_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canShowInteractions = _selectedDrugs.length >= 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medical Drug Checker'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Search row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _onSearch(),
                      decoration: InputDecoration(
                        labelText: 'Enter drug name',
                        hintText: 'e.g., Advil or ibuprofen',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: 'Search in FDA',
                          icon: const Icon(Icons.search),
                          onPressed: _onSearch,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: 'Add to selection',
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                      onPressed: _addSelected,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Selection chips
              if (_selectedDrugs.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _selectedDrugs
                        .map((name) => Chip(
                              label: Text(name),
                              onDeleted: () => _removeSelected(name),
                            ))
                        .toList(),
                  ),
                ),

              const SizedBox(height: 12),

              // Info panel for current query
              Expanded(
                child: SingleChildScrollView(
                  child: _buildDrugPanel(),
                ),
              ),

              const SizedBox(height: 8),

              // Show interactions -> next page
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: canShowInteractions ? _goToInteractions : null,
                  child: const Text('Show interactions'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String? badge;
  final List<String> lines;
  final IconData statusIcon;

  const _InfoCard({
    required this.title,
    required this.lines,
    required this.statusIcon,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(statusIcon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: theme.colorScheme.secondaryContainer,
                  ),
                  child: Text(
                    badge!,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
            ]),
            const SizedBox(height: 12),
            ...lines.where((l) => l.trim().isNotEmpty).map(
                  (l) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(l),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class InteractionsPage extends StatefulWidget {
  final List<String> selectedDrugs;

  const InteractionsPage({super.key, required this.selectedDrugs});

  @override
  State<InteractionsPage> createState() => _InteractionsPageState();
}

class _InteractionsPageState extends State<InteractionsPage> {
  bool _loading = false;
  String? _resultText; // Replace with parsed structured results later
  String? _error;

  Future<void> _computeInteractions() async {
    setState(() {
      _loading = true;
      _resultText = null;
      _error = null;
    });

    try {
      // TODO: point at backend (FastAPI)
      // For now, we just echo the list.
      await Future.delayed(const Duration(seconds: 1));
      _resultText =
          'Selected drugs:\n- ${widget.selectedDrugs.join('\n- ')}\n\n(Connect this screen to your backend /agent/interactions endpoint to compute interaction risks using FDA labels + AI or RxNorm APIs.)';
    } catch (e) {
      _error = 'Failed to compute interactions: $e';
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _computeInteractions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drug Interactions'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Text(_error!)
                  : SingleChildScrollView(
                      child: Text(
                        _resultText ?? 'No result',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
        ),
      ),
    );
  }
}

extension _StringX on String {
  String ifEmpty(String Function() alt) =>
      isEmpty ? alt() : this;
}
