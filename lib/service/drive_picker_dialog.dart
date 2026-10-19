import 'dart:async';

import 'package:flutter/material.dart';


import 'google_drive_picker_service.dart';

class DriveFilePickerDialog extends StatefulWidget {
  final GoogleDrivePickerService service;

  const DriveFilePickerDialog({super.key, required this.service});

  @override
  State<DriveFilePickerDialog> createState() => _DriveFilePickerDialogState();
}

class _DriveFilePickerDialogState extends State<DriveFilePickerDialog> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  final List<DrivePickedFile> _files = [];
  String? _nextPageToken;
  bool _loading = true; // first page
  bool _loadingMore = false;
  bool _opening = false; // downloading selected file
  String? _error;

  Timer? _debounce;
  int _requestId = 0; // ignore stale responses

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(reset: true));
    setState(() {}); // refresh clear button
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 200 && _nextPageToken != null && !_loadingMore && !_loading) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    final id = ++_requestId;

    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _nextPageToken = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final page = await widget.service.searchDriveFiles(
        query: _searchController.text,
        pageToken: reset ? null : _nextPageToken,
      );
      if (!mounted || id != _requestId) return;

      setState(() {
        if (reset) _files.clear();
        _files.addAll(page.files);
        _nextPageToken = page.nextPageToken;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = 'Could not load files. Please try again.';
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _select(DrivePickedFile file) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final selected = await widget.service.getFileById(file.id);
      if (mounted) Navigator.pop(context, selected);
    } catch (_) {
      if (mounted) {
        setState(() => _opening = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to open file')));
      }
    }
  }

  IconData _iconForMime(String? mimeType) {
    if (mimeType == null) return Icons.insert_drive_file_outlined;
    if (mimeType.contains('folder')) return Icons.folder_outlined;
    if (mimeType.contains('image')) return Icons.image_outlined;
    if (mimeType.contains('spreadsheet')) return Icons.table_chart_outlined;
    if (mimeType.contains('document')) return Icons.description_outlined;
    if (mimeType.contains('presentation')) return Icons.slideshow_outlined;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: size.height * 0.8),
        child: SizedBox(
          width: 420,
          height: 560,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                    child: Row(
                      children: [
                        Icon(Icons.add_to_drive_outlined, color: Colors.blue),
                        const SizedBox(width: 12),
                        Text('Google Drive', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ),
                  // ── Search bar ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) {
                        _debounce?.cancel();
                        _load(reset: true);
                      },
                      decoration: InputDecoration(
                        hintText: 'Search in Drive',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _debounce?.cancel();
                            _load(reset: true);
                          },
                        ),
                        isDense: true,
                        filled: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: _buildBody(theme)),
                ],
              ),
              if (_opening)
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: ColoredBox(
                      color: Colors.black26,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            TextButton(onPressed: () => _load(reset: true), child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_files.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(searching ? Icons.search_off : Icons.folder_off_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(searching ? 'No files match "${_searchController.text.trim()}"' : 'No files found', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _files.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        if (index >= _files.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }

        final file = _files[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _select(file),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(_iconForMime(file.mimeType), size: 18, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                        if (file.mimeType != null)
                          Text(file.mimeType!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: theme.colorScheme.outline),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}