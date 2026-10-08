import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../features/organization/organization.dart';
import '../features/production/production.dart';
import '../widgets/workspace_photo_background.dart';

enum _WorkQueueFilter { all, inspection, blocked }

class WorksScreen extends StatefulWidget {
  final String? organizationId;
  final String currentUserId;
  final OrganizationAccess organizationAccess;
  final ProductionWorkflowService workflowService;
  final CustomerDirectoryService? customerDirectoryService;
  final ProductionJobService? productionJobService;
  final ValueChanged<ProductionComparisonTarget> onOpenComparison;
  final ValueChanged<ProductionChatTarget> onOpenChat;
  final ProductionWorkView initialView;
  final bool openCreateOnMount;
  final bool overlayMode;
  final VoidCallback? onClose;

  const WorksScreen({
    super.key,
    required this.organizationId,
    this.currentUserId = '',
    required this.organizationAccess,
    required this.workflowService,
    this.customerDirectoryService,
    this.productionJobService,
    required this.onOpenComparison,
    required this.onOpenChat,
    this.initialView = ProductionWorkView.active,
    this.openCreateOnMount = false,
    this.overlayMode = false,
    this.onClose,
  });

  @override
  State<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends State<WorksScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;
  StreamSubscription<void>? _workChanges;
  late ProductionWorkView _view;
  _WorkQueueFilter _queueFilter = _WorkQueueFilter.all;
  List<ProductionWorkSummary> _items = const [];
  List<ProductionWorkSummary> _activeSearchItems = const [];
  List<ProductionWorkSummary> _archivedSearchItems = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _detailLoading = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    if (widget.organizationId != null) {
      _loadFirstPage();
      _watchWorks();
    }
    if (widget.openCreateOnMount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _canCreateWork) _createWork();
      });
    }
  }

  @override
  void didUpdateWidget(covariant WorksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId) {
      _workChanges?.cancel();
      if (widget.organizationId != null) {
        _loadFirstPage();
        _watchWorks();
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _realtimeDebounce?.cancel();
    _workChanges?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _watchWorks() {
    final organizationId = widget.organizationId;
    if (organizationId == null) return;
    _workChanges = widget.workflowService.watchWorks(organizationId).listen(
      (_) {
        _realtimeDebounce?.cancel();
        _realtimeDebounce = Timer(const Duration(milliseconds: 250), () {
          if (mounted && !_loading && !_loadingMore && !_detailLoading) {
            _reloadSelected();
          }
        });
      },
      onError: (_) {
        // Manual refresh remains available if Realtime is temporarily offline.
      },
    );
  }

  Future<void> _loadFirstPage() async {
    final organizationId = widget.organizationId;
    if (organizationId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final search = _searchController.text.trim();
      if (search.isNotEmpty && !widget.overlayMode) {
        final pages = await Future.wait([
          widget.workflowService.listWorks(
            organizationId: organizationId,
            search: search,
            view: ProductionWorkView.active,
          ),
          widget.workflowService.listWorks(
            organizationId: organizationId,
            search: search,
            view: ProductionWorkView.archived,
          ),
        ]);
        if (!mounted) return;
        setState(() {
          _activeSearchItems = pages[0].items;
          _archivedSearchItems = pages[1].items;
          _items = _view == ProductionWorkView.active
              ? pages[0].items
              : pages[1].items;
          _hasMore = false;
          _loading = false;
        });
        return;
      }
      final page = await widget.workflowService.listWorks(
        organizationId: organizationId,
        search: search,
        view: _view,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _activeSearchItems = const [];
        _archivedSearchItems = const [];
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить работы: $error';
      });
    }
  }

  Future<void> _loadMore() async {
    final organizationId = widget.organizationId;
    if (organizationId == null ||
        _loadingMore ||
        _items.isEmpty ||
        _searchController.text.trim().isNotEmpty) {
      return;
    }
    final last = _items.last;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.workflowService.listWorks(
        organizationId: organizationId,
        search: _searchController.text,
        view: _view,
        cursorUpdatedAt: last.updatedAt,
        cursorId: last.jobId,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = 'Не удалось загрузить следующую страницу: $error';
      });
    }
  }

  Future<void> _reloadSelected() async {
    await _loadFirstPage();
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      _loadFirstPage,
    );
  }

  bool get _canCreateWork =>
      widget.customerDirectoryService != null &&
      widget.productionJobService != null &&
      widget.organizationAccess.role == OrganizationRole.employee &&
      widget.organizationAccess.functions.contains(
        OrganizationMemberFunction.inspectionSpecialist,
      );

  List<ProductionWorkSummary> get _visibleItems => _items.where((work) {
        return switch (_queueFilter) {
          _WorkQueueFilter.all => true,
          _WorkQueueFilter.inspection =>
            work.stage == ProductionStage.qualityControl,
          _WorkQueueFilter.blocked =>
            work.flowState == ProductionFlowState.blocked,
        };
      }).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    if (widget.organizationId == null) {
      return const Center(
        child: Text('Реестр работ доступен в организации.'),
      );
    }
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              if (_error != null) ...[
                const SizedBox(height: 8),
                _errorBanner(),
              ],
              const SizedBox(height: 8),
              Expanded(child: _sectionBody()),
            ],
          ),
        ),
      ),
    );
    if (widget.overlayMode) {
      return Material(
        color: const Color(0xF2EEF3F5),
        elevation: 22,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }
    return Stack(
      children: [
        const Positioned.fill(child: WorkspacePhotoBackground()),
        Positioned.fill(child: content),
      ],
    );
  }

  Widget _sectionBody() {
    if (_searchController.text.trim().isNotEmpty && !widget.overlayMode) {
      return _globalSearchList();
    }
    return _workList();
  }

  Widget _header() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF2F8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xAAFFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.work_outline_rounded, color: AppTheme.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.overlayMode
                        ? _view == ProductionWorkView.active
                            ? 'Проверка'
                            : 'Архив'
                        : 'Работа',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.graphite,
                    ),
                  ),
                ),
                if (_canCreateWork && _view == ProductionWorkView.active) ...[
                  FilledButton.icon(
                    key: const ValueKey('create-production-work'),
                    onPressed: _loading ? null : _createWork,
                    icon: const Icon(Icons.add_rounded, size: 19),
                    label: const Text('Новая работа'),
                  ),
                  const SizedBox(width: 4),
                ],
                if (widget.onClose != null)
                  IconButton(
                    key: const ValueKey('close-work-register'),
                    tooltip: 'Закрыть список',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: _loading ? null : _loadFirstPage,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 680) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _worksSearchField(),
                      if (_showHeaderControls) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: _workViewControls(),
                        ),
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: _worksSearchField()),
                    if (_showHeaderControls) ...[
                      const SizedBox(width: 8),
                      _workViewControls(),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _worksSearchField() => TextField(
        key: const ValueKey('works-search'),
        controller: _searchController,
        onChanged: (value) {
          setState(() {});
          _onSearchChanged(value);
        },
        decoration: InputDecoration(
          hintText: 'Найти по номеру работы или заказчику',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Очистить',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    _loadFirstPage();
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
          isDense: true,
        ),
      );

  bool get _showHeaderControls =>
      !widget.overlayMode ||
      (_view == ProductionWorkView.active &&
          widget.organizationAccess.role != OrganizationRole.customer);

  Widget _workViewControls() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.overlayMode)
            SegmentedButton<ProductionWorkView>(
              key: const ValueKey('work-view-switch'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ProductionWorkView.active,
                  icon: Icon(Icons.play_arrow_rounded),
                  label: Text('Продолжить'),
                ),
                ButtonSegment(
                  value: ProductionWorkView.archived,
                  icon: Icon(Icons.archive_outlined),
                  label: Text('Архив'),
                ),
              ],
              selected: {_view},
              onSelectionChanged: _searchController.text.trim().isNotEmpty
                  ? null
                  : (values) async {
                      final value = values.first;
                      setState(() {
                        _view = value;
                        _queueFilter = _WorkQueueFilter.all;
                      });
                      await _loadFirstPage();
                    },
            ),
          if (_view == ProductionWorkView.active &&
              _searchController.text.trim().isEmpty &&
              widget.organizationAccess.role != OrganizationRole.customer) ...[
            if (!widget.overlayMode) const SizedBox(width: 8),
            _queueFilterButton(),
          ],
        ],
      );

  Widget _queueFilterButton() => PopupMenuButton<_WorkQueueFilter>(
        tooltip: 'Очередь работ',
        initialValue: _queueFilter,
        onSelected: (value) => setState(() => _queueFilter = value),
        itemBuilder: (_) => const [
          PopupMenuItem(
              value: _WorkQueueFilter.all, child: Text('Все в работе')),
          PopupMenuItem(
            value: _WorkQueueFilter.inspection,
            child: Text('На проверке'),
          ),
          PopupMenuItem(
            value: _WorkQueueFilter.blocked,
            child: Text('Остановлены'),
          ),
        ],
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.line),
            borderRadius: BorderRadius.circular(12),
            color: AppTheme.surface,
          ),
          child: Row(children: [
            const Icon(Icons.filter_list_rounded, size: 18),
            const SizedBox(width: 6),
            Text(switch (_queueFilter) {
              _WorkQueueFilter.all => 'Все',
              _WorkQueueFilter.inspection => 'На проверке',
              _WorkQueueFilter.blocked => 'Стоп',
            }),
          ]),
        ),
      );

  Widget _errorBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE7E5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4AAA5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 18, color: Color(0xFFA82820)),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!, maxLines: 2)),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _error = null),
              icon: const Icon(Icons.close, size: 17),
            ),
          ],
        ),
      );

  Widget _workList() {
    final items = _visibleItems;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _searchController.text.trim().isEmpty
                          ? 'В этом разделе пока нет работ.'
                          : 'По этому запросу ничего не найдено.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.graphiteSoft),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == items.length) {
                      return Padding(
                        padding: const EdgeInsets.all(10),
                        child: OutlinedButton.icon(
                          onPressed: _loadingMore ? null : _loadMore,
                          icon: _loadingMore
                              ? const SizedBox.square(
                                  dimension: 15,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.expand_more_rounded),
                          label: const Text('Показать ещё'),
                        ),
                      );
                    }
                    return _workRow(items[index]);
                  },
                ),
    );
  }

  Widget _globalSearchList() {
    if (_loading) {
      return const DecoratedBox(
        decoration: BoxDecoration(color: AppTheme.surface),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_activeSearchItems.isEmpty && _archivedSearchItems.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.line),
        ),
        child: const Center(
          child: Text(
            'По этому запросу ничего не найдено.',
            style: TextStyle(color: AppTheme.graphiteSoft),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: ListView(
        children: [
          if (_activeSearchItems.isNotEmpty) ...[
            _searchGroupHeader(
              'В работе',
              _activeSearchItems.length,
              Icons.play_arrow_rounded,
            ),
            ..._activeSearchItems.map(_workRow),
          ],
          if (_archivedSearchItems.isNotEmpty) ...[
            _searchGroupHeader(
              'Архив',
              _archivedSearchItems.length,
              Icons.archive_outlined,
            ),
            ..._archivedSearchItems.map(_workRow),
          ],
        ],
      ),
    );
  }

  Widget _searchGroupHeader(String label, int count, IconData icon) =>
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        color: AppTheme.surfaceMuted,
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.blue),
            const SizedBox(width: 7),
            Text(
              '$label · $count',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppTheme.graphite,
              ),
            ),
          ],
        ),
      );

  Widget _workRow(ProductionWorkSummary work) {
    final blocked = work.flowState == ProductionFlowState.blocked;
    final canOpenComparison =
        widget.overlayMode && work.jobStatus == 'active' && work.canBlock;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('work-row-${work.jobId}'),
        onTap: canOpenComparison ? () => _openLatestCheck(work) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.line)),
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 42,
                decoration: BoxDecoration(
                  color: blocked
                      ? const Color(0xFFC8463B)
                      : work.flowState == ProductionFlowState.completed ||
                              work.jobStatus != 'active'
                          ? const Color(0xFF548259)
                          : AppTheme.blue,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.jobNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.graphite,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      work.customerName.isEmpty
                          ? 'Заказчик уточняется'
                          : work.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.graphiteSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxWidth: 180),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: blocked
                      ? const Color(0xFFFFE7E5)
                      : work.jobStatus == 'active'
                          ? const Color(0xFFDCEBED)
                          : const Color(0xFFE1EEE2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  work.isCustomerView
                      ? work.customerStatus
                      : blocked
                          ? 'Остановлена'
                          : work.jobStatus == 'active'
                              ? 'В работе'
                              : 'Выполнена',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: blocked
                        ? const Color(0xFFA22D25)
                        : const Color(0xFF32727A),
                  ),
                ),
              ),
              if (canOpenComparison)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppTheme.graphiteSoft,
                  ),
                ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                key: ValueKey('work-menu-${work.jobId}'),
                tooltip: 'Действия',
                onSelected: (action) => _handleWorkAction(action, work),
                itemBuilder: (_) => _workMenuItems(work),
                icon: const Icon(Icons.more_vert_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _workMenuItems(ProductionWorkSummary work) {
    final active = work.jobStatus == 'active';
    return [
      if (!widget.overlayMode && active && work.canBlock)
        const PopupMenuItem(
          value: 'continue',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.play_arrow_rounded),
            title: Text('Продолжить проверку'),
          ),
        ),
      if (!active && work.canRestore)
        const PopupMenuItem(
          value: 'repeat',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.replay_rounded),
            title: Text('Повторная проверка'),
          ),
        ),
      const PopupMenuItem(
        value: 'history',
        child: ListTile(
          dense: true,
          leading: Icon(Icons.fact_check_outlined),
          title: Text('Результаты и история'),
        ),
      ),
      const PopupMenuItem(
        value: 'customer-chat',
        child: ListTile(
          dense: true,
          leading: Icon(Icons.chat_bubble_outline_rounded),
          title: Text('Чат по работе'),
        ),
      ),
      if (active && work.canComplete)
        const PopupMenuItem(
          value: 'complete',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.task_alt_rounded),
            title: Text('Завершить работу'),
          ),
        ),
      if (!active && work.canRestore)
        const PopupMenuItem(
          value: 'restore',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.unarchive_outlined),
            title: Text('Вернуть в работу'),
          ),
        ),
    ];
  }

  Future<void> _handleWorkAction(
    String action,
    ProductionWorkSummary work,
  ) async {
    switch (action) {
      case 'continue':
        return _openLatestCheck(work);
      case 'repeat':
        return _repeatCheck(work);
      case 'history':
        return _showWorkHistory(work);
      case 'customer-chat':
        widget.onOpenChat(
          ProductionChatTarget(
            work: work,
            channel: ProductionChatChannel.customer,
          ),
        );
        return;
      case 'complete':
        return _completeWorkFromMenu(work);
      case 'restore':
        return _restoreWorkFromMenu(work);
    }
  }

  Future<ProductionWorkDetail?> _loadWorkForAction(
    ProductionWorkSummary work,
  ) async {
    setState(() {
      _detailLoading = true;
      _error = null;
    });
    try {
      final detail = await widget.workflowService.loadWork(work.jobId);
      if (!mounted) return null;
      setState(() {
        _detailLoading = false;
      });
      return detail;
    } catch (error) {
      if (!mounted) return null;
      setState(() {
        _detailLoading = false;
        _error = 'Не удалось открыть работу: $error';
      });
      return null;
    }
  }

  ProductionWorkUnit? _latestUnit(ProductionWorkDetail detail) {
    ProductionWorkUnit? latest;
    for (final batch in detail.batches) {
      for (final unit in batch.units) {
        if (latest == null || unit.createdAt.isAfter(latest.createdAt)) {
          latest = unit;
        }
      }
    }
    return latest;
  }

  Future<void> _openLatestCheck(ProductionWorkSummary work) async {
    var detail = await _loadWorkForAction(work);
    if (detail == null || !mounted) return;
    var unit = _latestUnit(detail);
    try {
      if (detail.batches.isEmpty) {
        await widget.workflowService.createBatch(
          jobId: work.jobId,
          employeeUserId:
              widget.currentUserId.isEmpty ? null : widget.currentUserId,
          reason: 'Начата проверка образца',
        );
        detail = await widget.workflowService.loadWork(work.jobId);
      }
      if (unit == null && detail.batches.isNotEmpty) {
        await widget.workflowService.createUnit(
          batchId: detail.batches.first.id,
          type: ProductionUnitType.stack,
        );
        detail = await widget.workflowService.loadWork(work.jobId);
        unit = _latestUnit(detail);
      }
      if (!mounted || unit == null) return;
      widget.onOpenComparison(
        ProductionComparisonTarget(work: detail.summary, unit: unit),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось начать проверку: $error');
    }
  }

  Future<void> _repeatCheck(ProductionWorkSummary work) async {
    try {
      await widget.workflowService.restoreWork(work.jobId);
      if (!mounted) return;
      final restored = ProductionWorkSummary(
        jobId: work.jobId,
        jobNumber: work.jobNumber,
        customerId: work.customerId,
        customerName: work.customerName,
        jobStatus: 'active',
        stage: work.stage,
        flowState: ProductionFlowState.ready,
        activeBlockCount: 0,
        updatedAt: DateTime.now(),
        canAdvance: work.canAdvance,
        canAssignControllers: work.canAssignControllers,
        canBlock: work.canBlock,
        canUnblock: work.canUnblock,
        isCustomerView: work.isCustomerView,
        canCreateBatch: work.canCreateBatch,
        canComplete: work.canComplete,
        canRestore: false,
      );
      await _openLatestCheck(restored);
      if (mounted) await _loadFirstPage();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Не удалось начать повторную проверку: $error');
      }
    }
  }

  Future<void> _showWorkHistory(ProductionWorkSummary work) async {
    final detail = await _loadWorkForAction(work);
    if (detail == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .9,
        child: _workHistorySheet(sheetContext, detail),
      ),
    );
  }

  Widget _workHistorySheet(
    BuildContext sheetContext,
    ProductionWorkDetail detail,
  ) {
    final work = detail.summary;
    final units = detail.batches.expand((batch) => batch.units).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      work.jobNumber,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      work.customerName,
                      style: const TextStyle(color: AppTheme.graphiteSoft),
                    ),
                  ],
                ),
              ),
              _stateBadge(work.flowState),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Проверки образцов',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              if (units.isEmpty)
                const Text('Проверок пока нет.')
              else
                ...units.map(
                  (unit) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      unit.state == ProductionUnitState.blocked
                          ? Icons.block_rounded
                          : Icons.fact_check_outlined,
                      color: unit.state == ProductionUnitState.blocked
                          ? const Color(0xFFA82820)
                          : const Color(0xFF417C50),
                    ),
                    title: Text('Образец №${unit.number}'),
                    subtitle: Text(
                      'Сравнений: ${unit.attemptCount}'
                      '${unit.latestScore == null ? '' : ' · ${unit.latestScore!.toStringAsFixed(1)}%'}',
                    ),
                    trailing: Text(unit.state.label),
                  ),
                ),
              const SizedBox(height: 18),
              const Text(
                'История работы',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              if (detail.history.isEmpty)
                const Text('История пока пуста.')
              else
                ...detail.history.map(_historyRow),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _completeWorkFromMenu(ProductionWorkSummary work) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Завершить работу?'),
        content: const Text(
          'Работа получит статус «Выполнена» и перейдёт в архив.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.workflowService.completeWork(work.jobId);
      if (mounted) await _loadFirstPage();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Не удалось завершить работу: $error');
      }
    }
  }

  Future<void> _restoreWorkFromMenu(ProductionWorkSummary work) async {
    try {
      await widget.workflowService.restoreWork(work.jobId);
      if (mounted) await _loadFirstPage();
    } catch (error) {
      if (mounted) setState(() => _error = 'Не удалось вернуть работу: $error');
    }
  }

  Widget _stateBadge(ProductionFlowState state) {
    final blocked = state == ProductionFlowState.blocked;
    final completed = state == ProductionFlowState.completed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: blocked
            ? const Color(0xFFFFE1DE)
            : completed
                ? const Color(0xFFE1EEE2)
                : const Color(0xFFDCEBED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: blocked
              ? const Color(0xFFD9857E)
              : completed
                  ? const Color(0xFF9EBD9F)
                  : AppTheme.workspaceChromeLine,
        ),
      ),
      child: Text(
        state.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: blocked
              ? const Color(0xFF9D2F27)
              : completed
                  ? const Color(0xFF3A6E37)
                  : const Color(0xFF286970),
        ),
      ),
    );
  }

  Widget _historyRow(ProductionStageEvent event) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: event.eventType == 'blocked'
                    ? const Color(0xFFC8463B)
                    : event.eventType == 'unblocked'
                        ? const Color(0xFF5D9672)
                        : AppTheme.blue,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _eventLabel(event),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  if (event.note.trim().isNotEmpty)
                    Text(event.note, style: const TextStyle(fontSize: 11)),
                  Text(
                    '${_formatDate(event.createdAt)}'
                    '${event.actorName.isEmpty ? '' : ' · ${event.actorName}'}',
                    style: const TextStyle(
                        fontSize: 9.5, color: AppTheme.graphiteSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  String _eventLabel(ProductionStageEvent event) => switch (event.eventType) {
        'created' => 'Работа создана · ${event.toStage.label}',
        'advanced' => 'Переведена: ${event.toStage.label}',
        'blocked' => 'Производство заблокировано',
        'unblocked' => 'Блокировка снята',
        'completed' => 'Работа завершена',
        'restored' => 'Работа возвращена из архива',
        _ => event.toStage.label,
      };

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _createWork() async {
    final organizationId = widget.organizationId;
    final customerService = widget.customerDirectoryService;
    final jobService = widget.productionJobService;
    if (organizationId == null ||
        customerService == null ||
        jobService == null) {
      return;
    }

    List<OrganizationCustomer> customers;
    List<ProductionWorker> workers;
    try {
      customers = await customerService.listCustomers(organizationId);
      workers =
          await widget.workflowService.listOrganizationWorkers(organizationId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось загрузить заказчиков: $error');
      return;
    }
    if (!mounted) return;

    var number = '';
    OrganizationCustomer? selectedCustomer;
    ProductionWorker? responsible = workers.isEmpty ? null : workers.first;
    var createCustomer = customers.isEmpty;
    var newCustomerName = '';
    String? validation;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новая работа'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Номер работы из техзадания',
                  ),
                  onChanged: (value) => number = value,
                ),
                const SizedBox(height: 10),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.business_outlined),
                      label: Text('Из списка'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.add_business_outlined),
                      label: Text('Новый заказчик'),
                    ),
                  ],
                  selected: {createCustomer},
                  onSelectionChanged: (values) => setDialogState(() {
                    createCustomer = values.first;
                    selectedCustomer = null;
                    validation = null;
                  }),
                ),
                const SizedBox(height: 10),
                if (createCustomer)
                  TextField(
                    key: const ValueKey('new-work-customer-name'),
                    decoration: const InputDecoration(
                      labelText: 'Название заказчика',
                    ),
                    onChanged: (value) => newCustomerName = value,
                  )
                else
                  Autocomplete<OrganizationCustomer>(
                    displayStringForOption: (customer) => customer.displayLabel,
                    optionsBuilder: (value) {
                      final query = value.text.trim().toLowerCase();
                      return customers.where(
                        (customer) =>
                            query.isEmpty ||
                            customer.code.toLowerCase().contains(query) ||
                            customer.name.toLowerCase().contains(query),
                      );
                    },
                    onSelected: (customer) {
                      selectedCustomer = customer;
                      setDialogState(() => validation = null);
                    },
                    fieldViewBuilder: (
                      context,
                      controller,
                      focusNode,
                      onSubmitted,
                    ) =>
                        TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Заказчик: код или название',
                      ),
                      onChanged: (value) {
                        if (selectedCustomer?.displayLabel != value) {
                          selectedCustomer = null;
                        }
                      },
                      onSubmitted: (_) => onSubmitted(),
                    ),
                  ),
                if (workers.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ProductionWorker>(
                    initialValue: responsible,
                    decoration: const InputDecoration(
                      labelText: 'Ответственный сотрудник',
                    ),
                    items: workers
                        .map((worker) => DropdownMenuItem(
                              value: worker,
                              child: Text(worker.label),
                            ))
                        .toList(),
                    onChanged: (value) => responsible = value,
                  ),
                ],
                if (validation != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      validation!,
                      style: const TextStyle(color: Color(0xFFA82820)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                if (number.trim().isEmpty) {
                  setDialogState(() => validation = 'Введите номер работы.');
                  return;
                }
                if (createCustomer && newCustomerName.trim().length < 2) {
                  setDialogState(
                    () => validation = 'Введите название нового заказчика.',
                  );
                  return;
                }
                if (!createCustomer && selectedCustomer == null) {
                  setDialogState(
                    () => validation = 'Выберите заказчика из списка.',
                  );
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) return;

    setState(() => _loading = true);
    try {
      var customerId = selectedCustomer?.id;
      if (createCustomer) {
        customerId = await customerService.saveCustomer(
          organizationId: organizationId,
          code: '',
          name: newCustomerName,
          managerUserId: responsible?.userId,
        );
      }
      final job = await jobService.openJob(
        organizationId: organizationId,
        jobNumber: number,
        customerId: customerId,
        responsibleUserId: responsible?.userId,
      );
      if (!mounted) return;
      _searchController.clear();
      _view = ProductionWorkView.active;
      await _loadFirstPage();
      if (!mounted) return;
      ProductionWorkSummary? created;
      for (final item in _items) {
        if (item.jobId == job.jobId) {
          created = item;
          break;
        }
      }
      if (created != null) await _openLatestCheck(created);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось создать работу: $error';
      });
    }
  }
}
