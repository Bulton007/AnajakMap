import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/localization/strings.dart';
import '../../core/network/api_client.dart';
import '../../core/network/providers.dart';
import '../../shared/components/components.dart';
import '../../shared/components/remote.dart';
import '../../shared/models/server_models.dart';
import 'connected_trips.dart';

class ConnectedGeneration extends ConsumerStatefulWidget {
  const ConnectedGeneration({
    super.key,
    required this.trip,
    required this.profile,
    this.replan = false,
    this.current = const [],
    this.draft,
  });
  final ServerTrip trip;
  final Json profile;
  final bool replan;
  final List<ServerActivity> current;
  final Json? draft;
  @override
  ConsumerState<ConnectedGeneration> createState() => _GenerationState();
}

class _GenerationState extends ConsumerState<ConnectedGeneration> {
  String? jobId, draftId, proposalId;
  int draftVersion = 0;
  bool busy = false, polling = false, stopped = false, completed = false;
  bool approvalStarted = false;
  Object? error;
  GenerationJob? job;
  List<ServerActivity> activities = [];
  List<Json> reservations = [];
  Set<int> selected = {};
  final requestKey = ApiClient.operationId(), saveKey = ApiClient.operationId();
  final cancel = CancelToken();
  String source = '';
  @override
  void initState() {
    super.initState();
    if (widget.draft != null) {
      final d = widget.draft!;
      activities = objects(
        d['activities'],
      ).map(ServerActivity.fromJson).toList();
      final info = object(d['itinerary']);
      draftId = string(info, 'id').isEmpty ? null : string(info, 'id');
      draftVersion = integer(info, 'version');
      source = string(info, 'source');
      completed = string(info, 'status') != 'DRAFT';
      selected = Set.from(List.generate(activities.length, (i) => i));
    }
  }

  @override
  void dispose() {
    stopped = true;
    cancel.cancel();
    super.dispose();
  }

  Future<void> start() async {
    setState(() {
      busy = true;
      error = null;
      stopped = false;
    });
    try {
      final repo = ref.read(repositoryProvider);
      reservations = await repo.reservations(widget.trip.id);
      final result = await repo.generate(
        widget.trip.id,
        object((await repo.profile())['preferences']),
        requestKey,
        replan: widget.replan,
      );
      jobId = string(result, 'jobId');
      final scope =
          '${ref.read(environmentProvider).normalizedUrl}|${widget.profile['id']}';
      await ref.read(databaseProvider).cache(scope, 'job:$jobId', {
        'jobId': jobId,
        'tripId': widget.trip.id,
        'replan': widget.replan,
      });
      if (mounted) {
        setState(() => busy = false);
        await poll();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          busy = false;
        });
      }
    }
  }

  Future<void> poll() async {
    if (jobId == null || polling) {
      return;
    }
    setState(() {
      polling = true;
      stopped = false;
      error = null;
    });
    try {
      for (var attempt = 0; attempt < 90 && !stopped; attempt++) {
        final next = await ref
            .read(repositoryProvider)
            .job(jobId!, cancel: cancel);
        if (!mounted || stopped) {
          break;
        }
        if (next.tripId != widget.trip.id) {
          throw const ApiFailure(
            "JOB_TRIP",
            "This job belongs to a different trip.",
          );
        }
        setState(() {
          job = next;
          if (next.status == 'SUCCEEDED') {
            activities = next.activities;
            selected = Set.from(List.generate(activities.length, (i) => i));
            source = string(next.result, 'source');
          }
        });
        if (next.finished) {
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    } catch (e) {
      if (mounted && !stopped) {
        setState(() => error = e);
      }
    }
    if (mounted) {
      setState(() => polling = false);
    }
  }

  Future<void> approve() async {
    if (busy || completed || selected.isEmpty) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      approvalStarted = true;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final chosen = [
        for (var i = 0; i < activities.length; i++)
          if (selected.contains(i)) activities[i],
      ];
      if (widget.replan) {
        proposalId ??= string(
          await repo.proposal(
            widget.trip.id,
            widget.trip.version,
            chosen,
            source,
            saveKey,
          ),
          'proposalId',
        );
        await repo.decideProposal(widget.trip.id, proposalId!, true);
      } else {
        if (draftId == null) {
          final saved = await repo.draft(
            widget.trip.id,
            chosen,
            source,
            saveKey,
          );
          draftId = string(saved, 'itineraryId');
          draftVersion = integer(saved, 'version');
        } else if (widget.draft != null) {
          final edited = await repo.editDraft(
            widget.trip.id,
            draftId!,
            draftVersion,
            chosen,
            source,
          );
          draftVersion = integer(edited, 'version');
        }
        await repo.approve(
          widget.trip.id,
          draftId!,
          draftVersion,
          widget.trip.version,
        );
      }
      if (mounted) {
        setState(() {
          completed = true;
          busy = false;
        });
        openScreen(
          context,
          ConnectedTripDetail(tripId: widget.trip.id, profile: widget.profile),
        );
      }
    } catch (e) {
      // An approval may commit even when its response is lost. Confirm its actual
      // server state before offering another attempt; never infer success offline.
      var confirmed = false;
      try {
        final repo = ref.read(repositoryProvider);
        if (proposalId != null) {
          confirmed = (await repo.proposals(widget.trip.id)).any(
            (p) =>
                string(p, 'id') == proposalId &&
                string(p, 'status') == 'APPROVED',
          );
        } else if (draftId != null) {
          confirmed =
              string(
                object(
                  (await repo.itinerary(widget.trip.id, draftId!))['itinerary'],
                ),
                'status',
              ) ==
              'APPROVED';
        }
      } catch (_) {
        /* Retain the original failure and operation identifiers. */
      }
      if (mounted) {
        setState(() {
          completed = confirmed;
          error = confirmed ? null : e;
          busy = false;
          if (draftId == null &&
              proposalId == null &&
              e is ApiFailure &&
              e.status == 400) {
            approvalStarted = false;
          }
        });
        if (confirmed) {
          openScreen(
            context,
            ConnectedTripDetail(
              tripId: widget.trip.id,
              profile: widget.profile,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.t(widget.replan ? 'changes' : 'reviewDraft')),
      ),
      body: PageBody(
        children: [
          Text(
            widget.trip.title,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          Text(
            '${widget.trip.destination} · ${widget.trip.startDate} – ${widget.trip.endDate}',
          ),
          const SizedBox(height: 16),
          Notice(context.t('aiTrustBody'), icon: Icons.verified_user_outlined),
          const SizedBox(height: 16),
          if (jobId == null && widget.draft == null) ...[
            FilledButton.icon(
              onPressed: busy ? null : start,
              icon: const Icon(Icons.auto_awesome),
              label: Text(context.t(busy ? 'loading' : 'generateNow')),
            ),
            TextButton(
              onPressed: () =>
                  remoteForm(context, 'jobRecovery', [
                    const InputSpec('jobId'),
                  ], submit: (body, _) async => body).then((result) {
                    if (result is Map && mounted) {
                      jobId = result['jobId'];
                      poll();
                    }
                  }),
              child: Text(context.t('jobRecovery')),
            ),
          ],
          if (jobId != null) ...[
            SelectableText('${context.t('jobId')}: $jobId'),
            const SizedBox(height: 12),
            if (polling) ...[
              const LinearProgressIndicator(),
              Text(context.t('jobPending')),
              TextButton(
                onPressed: () => setState(() => stopped = true),
                child: Text(context.t('stopWaiting')),
              ),
            ],
            if (!polling && job?.finished != true)
              OutlinedButton(
                onPressed: poll,
                child: Text(context.t('checkJob')),
              ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            Notice('$error', error: true),
          ],
          if (job?.status == 'FAILED')
            Notice('${context.t('jobFailed')}: ${job!.error}', error: true),
          if (activities.isNotEmpty) ...[
            Section(context.t('source')),
            Text(source.isEmpty ? context.t('sourceUnknown') : source),
            if (job != null)
              ServerResult({
                for (final key in ['updatedAt', 'estimate', 'mock'])
                  if (job!.result.containsKey(key)) key: job!.result[key],
              }),
            if (widget.replan) ...[
              Section(context.t('before')),
              for (final a in widget.current) _Activity(a),
              Notice(context.t('replanReview')),
              Section(context.t('reservations')),
              ServerResult(reservations),
            ],
            Section(context.t('after')),
            for (var i = 0; i < activities.length; i++)
              Card(
                child: CheckboxListTile(
                  value: selected.contains(i),
                  onChanged: busy || completed || approvalStarted
                      ? null
                      : (v) => setState(
                          () => v! ? selected.add(i) : selected.remove(i),
                        ),
                  title: Text(activities[i].title),
                  secondary: IconButton(
                    tooltip: context.t('edit'),
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: busy || completed || approvalStarted
                        ? null
                        : () async {
                            final a = activities[i];
                            final edited = await remoteForm(context, 'edit', [
                              InputSpec('title', initial: a.title),
                              InputSpec(
                                'startsAt',
                                initial: a.startsAt,
                                kind: InputKind.instant,
                              ),
                              InputSpec(
                                'endsAt',
                                initial: a.endsAt,
                                kind: InputKind.instant,
                              ),
                            ]);
                            if (edited is Map && mounted) {
                              setState(
                                () => activities[i] = ServerActivity.fromJson({
                                  ...a.toDraft(),
                                  ...object(edited),
                                }),
                              );
                            }
                          },
                  ),
                  subtitle: Text(
                    '${activities[i].startsAt} – ${activities[i].endsAt}\n${activities[i].source}',
                  ),
                ),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy || completed || selected.isEmpty ? null : approve,
              icon: const Icon(Icons.check),
              label: Text(
                context.t(
                  busy
                      ? 'loading'
                      : completed
                      ? 'serverSaved'
                      : 'approveServer',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (await confirmDialog(
                            context,
                            context.t('discard'),
                            context.t('discardConfirm'),
                          ) &&
                          context.mounted) {
                        if (proposalId != null) {
                          await runRequest(
                            context,
                            () => ref
                                .read(repositoryProvider)
                                .decideProposal(
                                  widget.trip.id,
                                  proposalId!,
                                  false,
                                ),
                          );
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      }
                    },
              child: Text(context.t('discard')),
            ),
          ],
        ],
      ),
    ),
  );
}

class _Activity extends StatelessWidget {
  const _Activity(this.activity);
  final ServerActivity activity;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(activity.title),
      subtitle: Text('${activity.startsAt} – ${activity.endsAt}'),
    ),
  );
}
