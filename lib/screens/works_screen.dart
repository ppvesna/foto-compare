import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../features/organization/organization.dart';
import '../features/production/production.dart';

class WorksScreen extends StatefulWidget {
  final String? organizationId;
  final OrganizationAccess organizationAccess;
  final ProductionWorkflowService workflowService;
  final CustomerDirectoryService? customerDirectoryService;
  final ProductionJobService? productionJobService;
  final ValueChanged<ProductionComparisonTarget> onOpenComparison;
  final ValueChanged<ProductionWorkSummary> onOpenChat;

  const WorksScreen({
    super.key,
    required this.organizationId,
    required this.organizationAccess,
    required this.workflowService,
    this.customerDirectoryService,
    this.productionJobService,
    required this.onOpenComparison,
    required this.onOpenChat,
  });

  @override
  State<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends State<WorksScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;
  StreamSubscription<void>? _workChanges;
  ProductionWorkView _view = ProductionWorkView.active;
  List<ProductionWorkSummary> _items = const [];
  ProductionWorkDetail? _detail;
  String? _selectedJobId;
  bool _loading = false;
  bool _loadingMore = false;
  bool _detailLoading = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.organizationId != null) {
      _loadFirstPage();
      _watchWorks();
    }
  }

  @override
  void didUpdateWidget(covariant WorksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organizationId != widget.organizationId) {
      _workChanges?.cancel();
      _selectedJobId = null;
      _detail = null;
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

  Future<void> _loadFirstPage({String? keepSelected}) async {
    final organizationId = widget.organizationId;
    if (organizationId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.workflowService.listWorks(
        organizationId: organizationId,
        search: _searchController.text,
        view: _view,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _hasMore = page.hasMore;
        _loading = false;
        if (keepSelected != null &&
            page.items.any((item) => item.jobId == keepSelected)) {
          _selectedJobId = keepSelected;
        } else if (_selectedJobId != null &&
            !page.items.any((item) => item.jobId == _selectedJobId)) {
          _selectedJobId = null;
          _detail = null;
        }
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
    if (organizationId == null || _loadingMore || _items.isEmpty) return;
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

  Future<void> _openWork(String jobId) async {
    setState(() {
      _selectedJobId = jobId;
      _detailLoading = true;
      _error = null;
    });
    try {
      final detail = await widget.workflowService.loadWork(jobId);
      if (!mounted || _selectedJobId != jobId) return;
      setState(() {
        _detail = detail;
        _detailLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detailLoading = false;
        _error = 'Не удалось открыть работу: $error';
      });
    }
  }

  Future<void> _reloadSelected() async {
    final jobId = _selectedJobId;
    await _loadFirstPage(keepSelected: jobId);
    if (jobId != null && mounted) await _openWork(jobId);
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 350),
      _loadFirstPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.organizationId == null) {
      return const Center(
        child: Text('Реестр работ доступен в организации.'),
      );
    }
    return ColoredBox(
      color: AppTheme.appBackground,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              _errorBanner(),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 820) {
                    return _selectedJobId == null
                        ? _workList()
                        : _detailPane(showBack: true);
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth * .42,
                        child: _workList(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _detailPane()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final canCreate = widget.customerDirectoryService != null &&
        widget.productionJobService != null &&
        (widget.organizationAccess.role == OrganizationRole.admin ||
            widget.organizationAccess.role == OrganizationRole.employee);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.work_outline_rounded, color: AppTheme.blue),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Работа',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.graphite,
                    ),
                  ),
                ),
                if (canCreate)
                  FilledButton.icon(
                    key: const ValueKey('create-production-work'),
                    onPressed: _createWork,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Новая работа'),
                  ),
                if (canCreate) const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: _loading ? null : _reloadSelected,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('works-search'),
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Номер работы или заказчик',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить',
                        onPressed: () {
                          _searchController.clear();
                          _loadFirstPage();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: ProductionWorkView.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final value = ProductionWorkView.values[index];
                  return ChoiceChip(
                    key: ValueKey('work-view-${value.name}'),
                    label: Text(value.label),
                    selected: _view == value,
                    onSelected: (_) {
                      if (_view == value) return;
                      setState(() {
                        _view = value;
                        _selectedJobId = null;
                        _detail = null;
                      });
                      _loadFirstPage();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
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
                  itemCount: _items.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _items.length) {
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
                    return _workRow(_items[index]);
                  },
                ),
    );
  }

  Widget _workRow(ProductionWorkSummary work) {
    final selected = work.jobId == _selectedJobId;
    final blocked = work.flowState == ProductionFlowState.blocked;
    return InkWell(
      key: ValueKey('work-row-${work.jobId}'),
      onTap: () => _openWork(work.jobId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFDCEBED) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: AppTheme.line)),
          borderRadius: selected ? BorderRadius.circular(9) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 42,
              decoration: BoxDecoration(
                color: blocked
                    ? const Color(0xFFC8463B)
                    : work.flowState == ProductionFlowState.completed
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
                  const SizedBox(height: 3),
                  Text(
                    work.isCustomerView
                        ? work.customerStatus
                        : blocked
                            ? '${work.stage.label} · блокировок ${work.activeBlockCount}'
                            : work.stage.label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: !work.isCustomerView && blocked
                          ? const Color(0xFFA22D25)
                          : const Color(0xFF32727A),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppTheme.graphiteSoft),
          ],
        ),
      ),
    );
  }

  Widget _detailPane({bool showBack = false}) {
    if (_detailLoading) {
      return _detailFrame(const Center(child: CircularProgressIndicator()));
    }
    final detail = _detail;
    if (detail == null) {
      return _detailFrame(
        const Center(
          child: Text(
            'Выберите работу слева.',
            style: TextStyle(color: AppTheme.graphiteSoft),
          ),
        ),
      );
    }
    final work = detail.summary;
    if (work.isCustomerView) {
      return _detailFrame(_customerDetail(detail, showBack: showBack));
    }
    final activeBlocks =
        detail.blocks.where((block) => block.isActive).toList();
    return _detailFrame(
      SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showBack)
                  IconButton(
                    tooltip: 'К списку',
                    onPressed: () => setState(() {
                      _selectedJobId = null;
                      _detail = null;
                    }),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work.jobNumber,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.graphite,
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
              ],
            ),
            const SizedBox(height: 14),
            _stageRail(work.stage, work.flowState),
            const SizedBox(height: 14),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                OutlinedButton.icon(
                  onPressed: () => widget.onOpenChat(work),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Открыть чат'),
                ),
                if (work.canAdvance && work.stage != ProductionStage.completed)
                  OutlinedButton.icon(
                    key: const ValueKey('advance-work-stage'),
                    onPressed: activeBlocks.isEmpty ? _advanceStage : null,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('Следующий этап'),
                  ),
                if (work.canCreateBatch)
                  OutlinedButton.icon(
                    key: const ValueKey('create-production-batch'),
                    onPressed: _createBatch,
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Новая партия'),
                  ),
                if (work.canComplete && work.jobStatus == 'active')
                  OutlinedButton.icon(
                    key: const ValueKey('complete-production-work'),
                    onPressed: activeBlocks.isEmpty ? _completeWork : null,
                    icon: const Icon(Icons.task_alt_rounded, size: 18),
                    label: const Text('Завершить работу'),
                  ),
                if (work.canRestore && work.jobStatus != 'active')
                  OutlinedButton.icon(
                    key: const ValueKey('restore-production-work'),
                    onPressed: _restoreWork,
                    icon: const Icon(Icons.unarchive_outlined, size: 18),
                    label: const Text('Вернуть в работу'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle('Партии и проверки', Icons.inventory_2_outlined),
            const SizedBox(height: 8),
            if (detail.batches.isEmpty)
              const Text('Партии ещё не созданы.')
            else
              ...detail.batches.map((batch) => _batchCard(batch, work)),
            if (activeBlocks.isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionTitle(
                  'Активные блокировки', Icons.report_problem_outlined),
              const SizedBox(height: 8),
              ...activeBlocks.map(_blockCard),
            ],
            const SizedBox(height: 18),
            _sectionTitle('История прохождения', Icons.timeline_rounded),
            const SizedBox(height: 8),
            if (detail.history.isEmpty)
              const Text('История пока пуста.')
            else
              ...detail.history.take(12).map(_historyRow),
          ],
        ),
      ),
    );
  }

  Widget _customerDetail(ProductionWorkDetail detail,
      {required bool showBack}) {
    final work = detail.summary;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            if (showBack)
              IconButton(
                tooltip: 'К списку',
                onPressed: () => setState(() {
                  _selectedJobId = null;
                  _detail = null;
                }),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(work.jobNumber,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w900)),
                  if (work.customerName.isNotEmpty)
                    Text(work.customerName,
                        style: const TextStyle(color: AppTheme.graphiteSoft)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: work.customerStatus == 'Выполнен'
                    ? const Color(0xFFE1EEE2)
                    : const Color(0xFFDCEBED),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(work.customerStatus,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ]),
          const SizedBox(height: 18),
          const Text(
            'Производственные детали, внутренние проверки и '
            'блокировки ведёт команда исполнителя. Всё, что требует '
            'вашего внимания, ответственный сотрудник отправит в чат.',
            style: TextStyle(color: AppTheme.graphiteSoft, height: 1.45),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => widget.onOpenChat(work),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Открыть чат'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _batchCard(ProductionBatch batch, ProductionWorkSummary work) {
    final details = [
      if (batch.employeeName.isNotEmpty) batch.employeeName,
      if (batch.material.isNotEmpty) batch.material,
      if (batch.format.isNotEmpty) batch.format,
      if (batch.machine.isNotEmpty) batch.machine,
      if (batch.inks.isNotEmpty) batch.inks,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF7F9FA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: batch == _detail?.batches.first,
          title: Text(batch.label,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(
            details.isEmpty ? batch.reason : details.join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          children: [
            if (batch.units.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Добавьте стопу или рулон для проверки.'),
              )
            else
              ...batch.units.map((unit) => _unitRow(unit, work)),
            if (work.canCreateBatch &&
                work.jobStatus == 'active' &&
                batch.id == _detail?.batches.first.id)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _addUnit(batch),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Добавить стопу или рулон'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _unitRow(ProductionWorkUnit unit, ProductionWorkSummary work) {
    final blocked = unit.state == ProductionUnitState.blocked;
    final approved = unit.state == ProductionUnitState.approved;
    return Container(
      key: ValueKey('production-unit-${unit.id}'),
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: blocked
            ? const Color(0xFFFFF3F1)
            : approved
                ? const Color(0xFFF0F7F1)
                : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: blocked
              ? const Color(0xFFE4AAA5)
              : approved
                  ? const Color(0xFFB8D2BA)
                  : AppTheme.line,
        ),
      ),
      child: Row(children: [
        Icon(unit.type == ProductionUnitType.stack
            ? Icons.layers_outlined
            : Icons.rotate_90_degrees_ccw_outlined),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(unit.label,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(
                '${unit.state.label}'
                '${unit.attemptCount == 0 ? '' : ' · сравнений ${unit.attemptCount}'}'
                '${unit.latestScore == null ? '' : ' · ${unit.latestScore!.toStringAsFixed(1)}%'}',
                style: const TextStyle(
                    fontSize: 10.5, color: AppTheme.graphiteSoft),
              ),
            ],
          ),
        ),
        if (work.jobStatus == 'active' && work.canBlock) ...[
          TextButton.icon(
            key: ValueKey('open-unit-comparison-${unit.id}'),
            onPressed: () => widget.onOpenComparison(
              ProductionComparisonTarget(work: work, unit: unit),
            ),
            icon: const Icon(Icons.compare_outlined, size: 17),
            label: Text(unit.attemptCount == 0 ? 'Проверить' : 'Повторить'),
          ),
          if (work.canBlock && !blocked)
            IconButton(
              tooltip: 'Заблокировать',
              onPressed: () => _blockUnit(unit),
              icon: const Icon(Icons.block_rounded, size: 19),
            ),
        ],
      ]),
    );
  }

  Widget _detailFrame(Widget child) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.line),
        ),
        child: child,
      );

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

  Widget _stageRail(ProductionStage current, ProductionFlowState state) {
    const stages = ProductionStage.values;
    return Semantics(
      label: 'Текущий этап: ${current.label}',
      child: Row(
        children: [
          for (var index = 0; index < stages.length; index++) ...[
            Expanded(
              child: Column(
                children: [
                  Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: index < current.index
                          ? const Color(0xFF5D9672)
                          : index == current.index
                              ? state == ProductionFlowState.blocked
                                  ? const Color(0xFFC8463B)
                                  : AppTheme.blue
                              : AppTheme.line,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    stages[index].label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.1,
                      fontWeight: index == current.index
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: index <= current.index
                          ? AppTheme.graphite
                          : AppTheme.graphiteSoft,
                    ),
                  ),
                ],
              ),
            ),
            if (index != stages.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) => Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.graphiteSoft),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppTheme.graphite,
            ),
          ),
        ],
      );

  Widget _blockCard(ProductionJobBlock block) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3F1),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFE4AAA5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    block.scopeLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (block.customerVisible)
                  const Tooltip(
                    message: 'Причина видна заказчику',
                    child: Icon(Icons.visibility_outlined, size: 17),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(block.reason),
            const SizedBox(height: 5),
            Text(
              '${block.stage.label} · ${_formatDate(block.createdAt)}'
              '${block.createdByName.isEmpty ? '' : ' · ${block.createdByName}'}',
              style:
                  const TextStyle(fontSize: 10, color: AppTheme.graphiteSoft),
            ),
            if (_detail?.summary.canUnblock == true) ...[
              const SizedBox(height: 7),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _resolveBlock(block),
                  icon: const Icon(Icons.lock_open_rounded, size: 17),
                  label: const Text('Снять блокировку'),
                ),
              ),
            ],
          ],
        ),
      );

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

  Future<void> _advanceStage() async {
    final detail = _detail;
    if (detail == null) return;
    final nextIndex = detail.summary.stage.index + 1;
    final next = ProductionStage.values[nextIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Перевести работу?'),
        content: Text('Следующий этап: ${next.label}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Перевести'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runAction(
        () => widget.workflowService.advanceStage(detail.summary.jobId));
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
    try {
      customers = await customerService.listCustomers(organizationId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось загрузить заказчиков: $error');
      return;
    }
    if (!mounted) return;
    if (customers.isEmpty) {
      setState(() {
        _error = 'Сначала добавьте заказчика в настройках организации.';
      });
      return;
    }

    var number = '';
    OrganizationCustomer? selectedCustomer;
    String? validation;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новая работа'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Номер работы из техзадания',
                  ),
                  onChanged: (value) => number = value,
                ),
                const SizedBox(height: 10),
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
              ],
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
                if (selectedCustomer == null) {
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
    if (submitted != true || selectedCustomer == null) return;

    setState(() => _loading = true);
    try {
      final job = await jobService.openJob(
        organizationId: organizationId,
        jobNumber: number,
        customerId: selectedCustomer!.id,
      );
      if (!mounted) return;
      _searchController.clear();
      _view = ProductionWorkView.active;
      await _loadFirstPage(keepSelected: job.jobId);
      if (mounted) await _openWork(job.jobId);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось создать работу: $error';
      });
    }
  }

  Future<void> _createBatch() async {
    final detail = _detail;
    if (detail == null) return;
    List<ProductionWorker> workers;
    try {
      workers = await widget.workflowService.listWorkers(detail.summary.jobId);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Не удалось загрузить сотрудников: $error');
      }
      return;
    }
    if (!mounted) return;
    ProductionWorker? employee = workers.isEmpty ? null : workers.first;
    final reason = TextEditingController(text: 'Новая партия');
    final machine = TextEditingController();
    final material = TextEditingController();
    final format = TextEditingController();
    final inks = TextEditingController();
    String? validation;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Новая партия'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (workers.isNotEmpty)
                  DropdownButtonFormField<ProductionWorker>(
                    initialValue: employee,
                    decoration: const InputDecoration(labelText: 'Исполнитель'),
                    items: workers
                        .map((worker) => DropdownMenuItem(
                              value: worker,
                              child: Text(worker.label),
                            ))
                        .toList(),
                    onChanged: (value) => employee = value,
                  ),
                const SizedBox(height: 9),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(
                    labelText: 'Причина новой партии',
                    hintText: 'Смена сотрудника, материала, формата…',
                  ),
                ),
                const SizedBox(height: 9),
                TextField(
                    controller: machine,
                    decoration: const InputDecoration(
                        labelText: 'Машина (необязательно)')),
                const SizedBox(height: 9),
                TextField(
                    controller: material,
                    decoration: const InputDecoration(
                        labelText: 'Материал (необязательно)')),
                const SizedBox(height: 9),
                TextField(
                    controller: format,
                    decoration: const InputDecoration(
                        labelText: 'Формат или ширина рулона')),
                const SizedBox(height: 9),
                TextField(
                    controller: inks,
                    decoration: const InputDecoration(
                        labelText: 'Краски (необязательно)')),
                if (validation != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(validation!,
                        style: const TextStyle(color: Color(0xFFA82820))),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length < 2) {
                  setDialogState(
                      () => validation = 'Укажите причину новой партии.');
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
    await _runAction(() => widget.workflowService.createBatch(
          jobId: detail.summary.jobId,
          employeeUserId: employee?.userId,
          reason: reason.text,
          machine: machine.text,
          material: material.text,
          format: format.text,
          inks: inks.text,
        ));
  }

  Future<void> _addUnit(ProductionBatch batch) async {
    final type = await showDialog<ProductionUnitType>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${batch.label}: что добавить?'),
        content: const Text(
            'Проверка и её окончательный статус будут привязаны к этому объекту.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена')),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, ProductionUnitType.stack),
            icon: const Icon(Icons.layers_outlined),
            label: const Text('Стопа'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(dialogContext, ProductionUnitType.roll),
            icon: const Icon(Icons.rotate_90_degrees_ccw_outlined),
            label: const Text('Рулон'),
          ),
        ],
      ),
    );
    if (type == null) return;
    await _runAction(
        () => widget.workflowService.createUnit(batchId: batch.id, type: type));
  }

  Future<void> _blockUnit(ProductionWorkUnit unit) async {
    final reason = TextEditingController();
    String? validation;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Заблокировать ${unit.fullLabel}?'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: reason,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Причина'),
              ),
              if (validation != null)
                Align(
                    alignment: Alignment.centerLeft,
                    child: Text(validation!,
                        style: const TextStyle(color: Color(0xFFA82820)))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена')),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().length < 3) {
                  setDialogState(() => validation = 'Кратко укажите причину.');
                  return;
                }
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Заблокировать'),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) return;
    await _runAction(() =>
        widget.workflowService.blockUnit(unitId: unit.id, reason: reason.text));
  }

  Future<void> _completeWork() async {
    final detail = _detail;
    if (detail == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Завершить работу?'),
        content:
            const Text('Заказ получит статус «Выполнен» и перейдёт в архив.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Завершить')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runAction(
        () => widget.workflowService.completeWork(detail.summary.jobId));
  }

  Future<void> _restoreWork() async {
    final detail = _detail;
    if (detail == null) return;
    await _runAction(
        () => widget.workflowService.restoreWork(detail.summary.jobId));
  }

  Future<void> _resolveBlock(ProductionJobBlock block) async {
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Снять блокировку'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Что исправлено (необязательно)',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Снять блокировку'),
          ),
        ],
      ),
    );
    if (submitted == true) {
      await _runAction(
        () => widget.workflowService.resolveBlock(
          block.id,
          note: controller.text,
        ),
      );
    }
    controller.dispose();
  }

  Future<void> _runAction<T>(Future<T> Function() action) async {
    setState(() => _detailLoading = true);
    try {
      await action();
      if (!mounted) return;
      await _reloadSelected();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detailLoading = false;
        _error = 'Операция не выполнена: $error';
      });
    }
  }
}
