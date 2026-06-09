/// A page of items plus the cursor (`after`) for the next page.
class Listing<T> {
  const Listing({required this.items, this.after});
  final List<T> items;
  final String? after;

  bool get hasMore => after != null && after!.isNotEmpty;
}
