import 'package:flutter/widgets.dart';

/// App-wide route observer so screens can react to being revealed again after a
/// pushed route (e.g. a post detail) is popped — via the [RouteAware] mixin's
/// `didPopNext`. Registered in the GoRouter `observers` list.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
