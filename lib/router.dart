import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/route_observer.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/compose/compose_post_screen.dart';
import 'features/history/history_screen.dart';
import 'features/legal/policy_screen.dart';
import 'features/home/home_shell.dart';
import 'features/inbox/compose_message_screen.dart';
import 'features/inbox/message_thread_screen.dart';
import 'features/multireddit/manage_multireddit_screen.dart';
import 'features/multireddit/multireddit_feed_screen.dart';
import 'features/post/post_detail_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/subreddit/subreddit_screen.dart';
import 'features/user/user_screen.dart';
import 'models/inbox_item.dart';
import 'models/post.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    observers: [appRouteObserver],
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth.isLoading) return null;
      final loggedIn = auth.valueOrNull != null;
      final atLogin = state.matchedLocation == '/login';
      if (!loggedIn) return atLogin ? null : '/login';
      if (atLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/', builder: (_, __) => const HomeShell()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/policy', builder: (_, __) => const PolicyScreen()),
      GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
      GoRoute(
        path: '/search',
        builder: (_, state) =>
            SearchScreen(initialSubreddit: state.uri.queryParameters['sr']),
      ),
      GoRoute(
        path: '/submit',
        builder: (_, state) => ComposePostScreen(
            initialSubreddit: state.uri.queryParameters['sr']),
      ),
      GoRoute(
        path: '/message',
        builder: (_, state) =>
            MessageThreadScreen(root: state.extra as InboxItem),
      ),
      GoRoute(
        path: '/compose_message',
        builder: (_, state) =>
            ComposeMessageScreen(initialTo: state.uri.queryParameters['to']),
      ),
      GoRoute(
        path: '/r/:name',
        builder: (_, state) =>
            SubredditScreen(name: state.pathParameters['name']!),
      ),
      GoRoute(
        path: '/u/:username',
        builder: (_, state) =>
            UserScreen(username: state.pathParameters['username']!),
      ),
      GoRoute(
        path: '/m/:username/:name',
        builder: (_, state) => MultiredditFeedScreen(
          username: state.pathParameters['username']!,
          name: state.pathParameters['name']!,
        ),
      ),
      GoRoute(
        path: '/m/:username/:name/manage',
        builder: (_, state) =>
            ManageMultiredditScreen(name: state.pathParameters['name']!),
      ),
      GoRoute(
        path: '/comments/:subreddit/:id',
        builder: (_, state) => PostDetailScreen(
          subreddit: state.pathParameters['subreddit']!,
          postId: state.pathParameters['id']!,
          initialPost: state.extra as Post?,
          focusCommentId: state.uri.queryParameters['comment'],
        ),
      ),
    ],
  );
});
