import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'item.dart';

const _ohosRecentRequestFallbackTtl = Duration(seconds: 10);
const _ohosFallbackRequestLimit = 50;

@visibleForTesting
List<TrackerInfo> buildOhosConnectionFallback(
  List<TrackerInfo> requests, {
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final threshold = current.subtract(_ohosRecentRequestFallbackTtl);
  final uniqueRequests = <TrackerInfo>[];

  for (final item in requests.reversed) {
    final alreadyExists = uniqueRequests.any(
      (current) => current.id == item.id,
    );
    if (!alreadyExists) {
      uniqueRequests.add(item);
    }
    if (uniqueRequests.length >= _ohosFallbackRequestLimit) {
      break;
    }
  }

  final recentRequests = uniqueRequests
      .where((item) => item.start.isAfter(threshold))
      .toList();
  return recentRequests.isNotEmpty ? recentRequests : uniqueRequests;
}

class ConnectionsView extends ConsumerStatefulWidget {
  const ConnectionsView({super.key});

  @override
  ConsumerState<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends ConsumerState<ConnectionsView> {
  static const _ohosPollInterval = Duration(milliseconds: 250);
  static const _defaultPollInterval = Duration(seconds: 1);
  static const _ohosSnapshotTtl = Duration(seconds: 5);

  final _connectionsStateNotifier = ValueNotifier<TrackerInfosState>(
    const TrackerInfosState(),
  );
  final ScrollController _scrollController = ScrollController();

  Timer? timer;
  List<TrackerInfo> _lastNonEmptyConnections = const [];
  DateTime? _lastNonEmptyConnectionsAt;

  List<Widget> _buildActions() {
    return [
      IconButton(
        onPressed: () async {
          coreController.closeConnections();
          await _updateConnections();
        },
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ];
  }

  void _onSearch(String value) {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      query: value,
    );
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  Future<void> _updateConnectionsTask() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await _updateConnections();
        timer = Timer(
          system.isOhos ? _ohosPollInterval : _defaultPollInterval,
          () async {
            _updateConnectionsTask();
          },
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _updateConnectionsTask();
  }

  Future<void> _updateConnections() async {
    final connections = await coreController.getConnections();
    if (connections.isNotEmpty) {
      _lastNonEmptyConnections = connections;
      _lastNonEmptyConnectionsAt = DateTime.now();
    }
    final shouldReuseLastSnapshot =
        system.isOhos &&
        connections.isEmpty &&
        _lastNonEmptyConnections.isNotEmpty &&
        _lastNonEmptyConnectionsAt != null &&
        DateTime.now().difference(_lastNonEmptyConnectionsAt!) <=
            _ohosSnapshotTtl;
    final recentRequestFallback =
        system.isOhos && connections.isEmpty && !shouldReuseLastSnapshot
        ? _recentRequestsFallback()
        : const <TrackerInfo>[];
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      trackerInfos: shouldReuseLastSnapshot
          ? _lastNonEmptyConnections
          : (recentRequestFallback.isNotEmpty
                ? recentRequestFallback
                : connections),
    );
  }

  List<TrackerInfo> _recentRequestsFallback() {
    return buildOhosConnectionFallback(ref.read(requestsProvider).list);
  }

  Future<void> _handleBlockConnection(String id) async {
    await coreController.closeConnection(id);
    await _updateConnections();
  }

  @override
  void dispose() {
    timer?.cancel();
    _connectionsStateNotifier.dispose();
    _scrollController.dispose();
    timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: appLocalizations.connections,
      onKeywordsUpdate: _onKeywordsUpdate,
      searchState: AppBarSearchState(onSearch: _onSearch),
      actions: _buildActions(),
      body: ValueListenableBuilder<TrackerInfosState>(
        valueListenable: _connectionsStateNotifier,
        builder: (context, state, _) {
          final connections = state.list;
          if (connections.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullTip(appLocalizations.connections),
              illustration: const ConnectionEmptyIllustration(),
            );
          }
          final items = connections
              .map<Widget>(
                (trackerInfo) => TrackerInfoItem(
                  key: Key(trackerInfo.id),
                  trackerInfo: trackerInfo,
                  onClickKeyword: (value) {
                    context.commonScaffoldState?.addKeyword(value);
                  },
                  trailing: IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(minimumSize: Size.zero),
                    icon: const Icon(Icons.block),
                    onPressed: () {
                      _handleBlockConnection(trackerInfo.id);
                    },
                  ),
                  detailTitle: appLocalizations.details(
                    appLocalizations.connection,
                  ),
                ),
              )
              .separated(const Divider(height: 0))
              .toList();
          return SuperListView.builder(
            controller: _scrollController,
            itemBuilder: (context, index) {
              return items[index];
            },
            itemCount: connections.length,
          );
        },
      ),
    );
  }
}
